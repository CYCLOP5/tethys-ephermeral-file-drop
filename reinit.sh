#!/bin/bash
set -euo pipefail

echo "--- 1. Running Ansible Playbook (Installing K3s) ---"
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/site.yml
cd ../..

echo "--- 2. Fetching New Cluster Details ---"
SERVER_SSH=$(cd infra/terraform && terraform output -raw k3s_server_ssh)
AGENT_SSHS=$(cd infra/terraform && terraform output -json k3s_agents_ssh | python3 -c "import sys, json; print(' '.join(json.load(sys.stdin)))")

SERVER_IP=$(echo "$SERVER_SSH" | awk '{print $NF}' | cut -d'@' -f2)
KEY=$(echo "$SERVER_SSH" | awk '{print $3}')

echo "Server IP: $SERVER_IP"

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

for agent_ssh in $AGENT_SSHS; do
    AGENT_IP=$(echo "$agent_ssh" | awk '{print $NF}' | cut -d'@' -f2)
    refresh_ecr "$AGENT_IP"
done

echo "--- 4. Applying Kubernetes Manifests ---"
ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@"$SERVER_IP" "mkdir -p ~/k8s"
ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@"$SERVER_IP" "rm -rf ~/k8s/*"
scp -o StrictHostKeyChecking=no -i "$KEY" -r deploy/k8s/* ec2-user@"$SERVER_IP":~/k8s/
ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@"$SERVER_IP" 'sudo kubectl apply -R -f ~/k8s/'

echo ""
echo "Frontend: http://$(cd infra/terraform && terraform output -raw alb_dns_name)"
