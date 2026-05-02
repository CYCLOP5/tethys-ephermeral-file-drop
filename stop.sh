#!/bin/bash
set -euo pipefail

REGION="us-east-1"
PROJECT="tethys"

echo "Finding all instances for project: $PROJECT..."
INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=running,pending" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

if [ -z "$INSTANCE_IDS" ]; then
    echo "No running instances found for project: $PROJECT"
    exit 0
fi

echo "Stopping instances: $INSTANCE_IDS"
aws ec2 stop-instances --region "$REGION" --instance-ids $INSTANCE_IDS

echo "Waiting for instances to stop..."
aws ec2 wait instance-stopped --region "$REGION" --instance-ids $INSTANCE_IDS

echo "All $PROJECT instances have been stopped."
