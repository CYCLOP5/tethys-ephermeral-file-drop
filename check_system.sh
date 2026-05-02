#!/bin/bash
set -euo pipefail

# --- Configuration ---
if [ -d "infra/terraform" ]; then
    SERVER_SSH=$(cd infra/terraform && terraform output -raw k3s_server_ssh)
    # Extract IP and key from "ssh -i <key> ec2-user@<ip>"
    KEY=$(echo "$SERVER_SSH" | awk '{print $3}')
    IP=$(echo "$SERVER_SSH" | awk '{print $4}' | cut -d'@' -f2)
else
    IP="44.200.55.17"
    KEY="~/.ssh/tethys-tf-key-2.pem"
fi

echo "--- Kubernetes Cluster Status ($IP) ---"
ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@$IP 'KC=/etc/rancher/k3s/k3s.yaml; sudo kubectl --kubeconfig=$KC get pods -n tethys -o wide'

echo ""
echo "--- Recent Vault (API) Logs ---"
ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@$IP 'KC=/etc/rancher/k3s/k3s.yaml; sudo kubectl --kubeconfig=$KC logs -n tethys deployment/vault --tail=10'

echo ""
echo "--- Wiper (Cleanup) Status ---"
ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@$IP 'KC=/etc/rancher/k3s/k3s.yaml; sudo kubectl --kubeconfig=$KC get cronjob -n tethys'
