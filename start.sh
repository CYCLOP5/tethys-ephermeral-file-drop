#!/bin/bash
set -euo pipefail

REGION="us-east-1"
PROJECT="tethys"

echo "Finding all instances for project: $PROJECT..."
INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=stopped,stopping" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

if [ -z "$INSTANCE_IDS" ]; then
    echo "No stopped instances found for project: $PROJECT"
    exit 0
fi

echo "Starting instances: $INSTANCE_IDS"
aws ec2 start-instances --region "$REGION" --instance-ids $INSTANCE_IDS

echo "Waiting for instances to be running..."
aws ec2 wait instance-running --region "$REGION" --instance-ids $INSTANCE_IDS

echo "All $PROJECT instances are now running."
echo "Note: Public IPs may have changed. You might need to update your SSH config or ALB target groups if not using elastic IPs."
