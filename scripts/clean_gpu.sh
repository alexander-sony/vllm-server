#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8000}"

echo ">>> Checking GPU processes"
nvidia-smi || true

echo ">>> Killing listener on port $PORT (if any)"
PID=$(lsof -t -i:$PORT -sTCP:LISTEN 2>/dev/null || true)
if [ -n "${PID}" ]; then
  echo "Killing PID=$PID"
  kill -9 "$PID" || true
else
  echo "No listener on $PORT"
fi

echo ">>> Killing vLLM/uvicorn workers (best effort)"
pkill -f "vllm serve"       || true
pkill -f "vllm.entrypoints" || true
pkill -f "uvicorn"          || true
pkill -f "api_server.py"    || true
pkill -f "engine_core"      || true
pkill -f "python.*vllm"     || true

echo ">>> Killing any remaining GPU compute apps"
PIDS=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | tr -d ' ' | sort -u || true)
if [ -n "${PIDS}" ]; then
  echo "PIDs: ${PIDS}"
  sudo kill -9 ${PIDS} || true
else
  echo "No remaining compute apps"
fi

echo ">>> Post-clean check"
nvidia-smi || true
