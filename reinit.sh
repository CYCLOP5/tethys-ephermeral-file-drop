#!/bin/bash
set -euo pipefail

echo "--- 1. Running Ansible Playbook (Installing K3s) ---"
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/site.yml
cd ../..

echo "--- 2. Fetching New Cluster Details ---"
SERVER_SSH=$(cd infra/terraform && terraform output -raw k3s_server_ssh)
AGENT_IPS=$(cd infra/terraform && terraform output -json k3s_agents_ssh | python3 -c "import sys, json; print(' '.join([s.split('@')[-1] for s in json.load(sys.stdin)]))")

SERVER_IP=$(echo "$SERVER_SSH" | awk '{print $NF}' | cut -d'@' -f2)
KEY=$(echo "$SERVER_SSH" | awk '{print $3}')

echo "Server IP: $SERVER_IP"
echo "Agent IPs: $AGENT_IPS"

echo "--- 3. Refreshing ECR Credentials on All Nodes ---"
refresh_ecr() {
    local ip=$1
    echo "  -> Refreshing ECR on $ip..."
    ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@"$ip" 'bash -s' <<'EOF'
        REGION="us-east-1"
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
        ECR_PASSWORD=$(aws ecr get-login-password --region "$REGION")
        sudo mkdir -p /etc/rancher/k3s
        sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOT
mirrors:
  "${REGISTRY}":
    endpoint:
      - "https://${REGISTRY}"
configs:
  "${REGISTRY}":
    auth:
      username: AWS
      password: "${ECR_PASSWORD}"
EOT
        if systemctl is-active --quiet k3s; then
            sudo systemctl restart k3s
        else
            sudo systemctl restart k3s-agent
        fi
EOF
}

refresh_ecr "$SERVER_IP"

for AGENT_IP in $AGENT_IPS; do
    refresh_ecr "$AGENT_IP"
done

ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@"$SERVER_IP" '
    if ! command -v helm &> /dev/null; then
        echo "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
'

echo "--- 4. Installing Nginx Ingress Controller ---"
scp -o StrictHostKeyChecking=no -i "$KEY" deploy/k8s/ingress/nginx-ingress-values.yaml ec2-user@"$SERVER_IP":/tmp/
ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@"$SERVER_IP" '
    KC=/etc/rancher/k3s/k3s.yaml
    sudo KUBECONFIG=$KC /usr/local/bin/helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    sudo KUBECONFIG=$KC /usr/local/bin/helm repo update
    sudo KUBECONFIG=$KC /usr/local/bin/helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx --create-namespace \
      -f /tmp/nginx-ingress-values.yaml
'

echo "Waiting for Ingress Controller to be ready..."
ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@"$SERVER_IP" '
    sudo kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=120s
'

echo "--- 5. Applying Kubernetes Manifests ---"
ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@"$SERVER_IP" "mkdir -p ~/k8s"
ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@"$SERVER_IP" "rm -rf ~/k8s/*"
scp -o StrictHostKeyChecking=no -i "$KEY" -r deploy/k8s/* ec2-user@"$SERVER_IP":~/k8s/

ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@"$SERVER_IP" 'sudo kubectl apply -f ~/k8s/namespace.yaml'
sleep 2

ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@"$SERVER_IP" '
    for f in $(find ~/k8s -name "*.yaml" ! -name "nginx-ingress-values.yaml" ! -name "namespace.yaml"); do
        echo "Applying $f..."
        sudo kubectl apply -f "$f"
    done
'

echo ""
echo "Frontend: http://$(cd infra/terraform && terraform output -raw alb_dns_name)"
