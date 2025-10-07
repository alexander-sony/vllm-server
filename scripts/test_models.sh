#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${BASE_URL:-http://${HOST:-127.0.0.1}:${PORT:-8000}/v1}"
AUTH_TOKEN="${AUTH_TOKEN:-dummy}"
echo "GET ${BASE_URL}/models"
curl -Ssf "${BASE_URL}/models" -H "Authorization: Bearer ${AUTH_TOKEN}" | python3 -m json.tool
