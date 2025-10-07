#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000/v1}"
MODEL_ID="${MODEL_ID:-openai/gpt-oss-20b}"
AUTH_TOKEN="${AUTH_TOKEN:-dummy}"

echo "=== tools test ==="
echo "BASE_URL: $BASE_URL"
echo "MODEL_ID: $MODEL_ID"

json=$(
curl -sS -X POST "${BASE_URL}/chat/completions" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_ID}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Add 41 and 1\"}],
    \"tools\": [{
      \"type\": \"function\",
      \"function\": {
        \"name\": \"add\",
        \"description\": \"Add two integers.\",
        \"parameters\": {
          \"type\": \"object\",
          \"properties\": {
            \"a\": {\"type\": \"integer\"},
            \"b\": {\"type\": \"integer\"}
          },
          \"required\": [\"a\", \"b\"]
        }
      }
    }],
    \"tool_choice\": \"auto\"
  }"
)

echo "$json" | python3 -m json.tool || true

# success if tool_calls appear
if echo "$json" | grep -q '"tool_calls"'; then
  echo "✅ tools supported"
  exit 0
else
  echo "❌ no tool_calls in response"
  exit 1
fi
