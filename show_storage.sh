#!/bin/bash
set -euo pipefail

# --- Configuration ---
if [ -d "infra/terraform" ]; then
    BUCKET=$(cd infra/terraform && terraform output -raw s3_bucket_name)
else
    BUCKET="tethys-dev-files-4acaaa0c"
fi
REGION="us-east-1"

echo "--- Current Files in S3 (Encrypted Blobs) ---"
echo "Bucket: $BUCKET"
aws s3 ls "s3://$BUCKET/files/" --region "$REGION" || echo "No files found."

echo ""
echo "--- Inspecting Latest File ---"
LATEST_FILE=$(aws s3 ls "s3://$BUCKET/files/" --region "$REGION" | sort | tail -n 1 | awk '{print $4}')

if [ -z "$LATEST_FILE" ]; then
    echo "No files to inspect."
    exit 0
fi

echo "File: $LATEST_FILE"
echo "Hex dump of first 64 bytes (shows it's random/encrypted data):"
aws s3 cp "s3://$BUCKET/files/$LATEST_FILE" - --region "$REGION" | head -c 64 | xxd
echo ""
echo "Note: The server has NO access to the decryption keys. This is just raw ciphertext."
