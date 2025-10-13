#!/usr/bin/env bash
set -euo pipefail
mode="${1:-smoke}"
PORT=$(grep ^PORT .env.active | cut -d= -f2)
KEY=$(grep ^VLLM_API_KEY .env.active | cut -d= -f2)
# Prefer explicit BIND_IP in env; fall back to 127.0.0.1
HOST=$(grep -E '^BIND_IP=' .env.active 2>/dev/null | cut -d= -f2 || echo "127.0.0.1")
[[ -z "$HOST" || "$HOST" == "0.0.0.0" ]] && HOST="127.0.0.1"

if [[ "$mode" == "models" ]]; then
  echo "GET /v1/models"
  curl -fsS "http://${HOST}:${PORT}/v1/models" -H "Authorization: Bearer ${KEY}" | jq .
  exit 0
fi

echo "Smoke: /v1/models"
curl -fsS "http://${HOST}:${PORT}/v1/models" -H "Authorization: Bearer ${KEY}" | jq .

echo
echo "Smoke: /v1/chat/completions"
MODEL=$(grep ^MODEL .env.active | cut -d= -f2)
curl -fsS "http://${HOST}:${PORT}/v1/chat/completions" \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_tokens\":8}" | jq .
echo
echo "OK ✅"
