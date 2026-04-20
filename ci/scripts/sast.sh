#!/usr/bin/env bash
# Run the full SAST bundle locally to mirror what Jenkins does.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

command -v gosec     >/dev/null || go install github.com/securego/gosec/v2/cmd/gosec@latest
command -v semgrep   >/dev/null || pip3 install --user --quiet semgrep
command -v trivy     >/dev/null || { echo "install trivy first"; exit 1; }

echo "==> gosec (vault)"
gosec -fmt=text ./services/vault/... || true

echo "==> gosec (wiper)"
gosec -fmt=text ./services/wiper/... || true

echo "==> semgrep (OWASP Top Ten + secrets)"
semgrep scan --config p/owasp-top-ten --config p/secrets --error "$ROOT" || true

echo "==> trivy fs (HIGH/CRITICAL)"
trivy fs --severity HIGH,CRITICAL --exit-code 0 --no-progress "$ROOT"
