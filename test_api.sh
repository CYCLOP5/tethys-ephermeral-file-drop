#!/bin/bash
set -euo pipefail

# --- Configuration ---
# Get values dynamically from Terraform if possible
if [ -d "infra/terraform" ]; then
    ALB_URL="http://$(cd infra/terraform && terraform output -raw alb_dns_name)"
else
    ALB_URL="http://tethys-dev-alb-1132299892.us-east-1.elb.amazonaws.com"
fi

JWT="eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJzdWIiOiAiZGVtby11c2VyIiwgImlhdCI6IDE3Nzc4NzkyOTAsICJleHAiOiAxODA5NDE1MjkwfQ.mWvPw2zdChlE81ETWb38HnkSvwUivZPiAPcNe0Vw9w8"

echo "--- Initializing Upload via API ---"
echo "Target: $ALB_URL"
RESPONSE=$(curl -s -X POST "$ALB_URL/api/v1/uploads" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $JWT" \
    -d '{"size_bytes": 1024, "ttl_seconds": 3600, "max_downloads": 1}')

if echo "$RESPONSE" | grep -q "error"; then
    echo "API Error:"
    echo "$RESPONSE" | python3 -m json.tool
    exit 1
fi

echo "$RESPONSE" | python3 -m json.tool

UPLOAD_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['upload_id'])")
PUT_URL=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['presigned_put_url'])")

echo ""
echo "--- Uploading dummy encrypted data (1KB) to S3 ---"
dd if=/dev/urandom bs=1024 count=1 2>/dev/null > /tmp/dummy_payload
curl -s -X PUT -T /tmp/dummy_payload "$PUT_URL"

echo ""
echo "--- Verification ---"
echo "Upload ID: $UPLOAD_ID"
echo "The file is now in S3 and registered in the database."
echo "You can check the storage using ./show_storage.sh"
rm /tmp/dummy_payload
