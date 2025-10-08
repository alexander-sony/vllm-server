# vLLM Server Management Guide

This document explains how to start, manage, and stop the **vLLM OpenAI-compatible API server** running inside a `screen` session.

---

## 🧠 Overview

The vLLM server provides an OpenAI-compatible API endpoint, typically used for local or remote inference (e.g., `openai/gpt-oss-20b`).

We use **GNU Screen** to keep the server running in the background, even after SSH disconnection.

---

## ⚙️ Prerequisites

- The virtual environment (`.venv`) is already set up inside this folder.
- The model weights are available or automatically downloaded.
- **Installation:** If vLLM is not installed, run `make install` to set up vLLM and dependencies. Note: Installation requires Python build tools (e.g., `python3-dev`, `build-essential`) to compile required modules.
- **Model Options:** The Makefile supports multiple models:
  - `make serve` - GPT-OSS 20B model (default)
  - `make serve-llama8b` - Llama 3.1 8B Instruct model (requires `HUGGING_FACE_HUB_TOKEN` environment variable)
- `make serve` is configured to start the server, e.g.:

  ```makefile
  serve:
  	source .venv/bin/activate && \
  	vllm serve openai/gpt-oss-20b --api-key dummy --port 8000 --host 127.0.0.1
  ```

   **Note:** For Llama models, authenticate with Hugging Face:
   ```bash
   uv run huggingface-cli login --token <your_token_here>
   ```

---

## 🚀 Start the Server in a Screen Session

1. SSH into the server:
   ```bash
   ssh <user>@<remote-ip>
   ```

2. Start a new `screen` session named `vllm` (check first any existing session...):
   ```bash
   screen -S vllm
   ```

3. From inside the session, start the server:
   ```bash
   make serve              # GPT-OSS 20B model (default)
   # OR
   make serve-llama8b      # Llama 3.1 8B Instruct model
   ```

4. Once you see:
   ```
   Starting HTTP server on 127.0.0.1:8000 ...
   ```
   Detach from the session (leaving it running) with:
   ```
   Ctrl + A  then  D
   ```

---

## 🦯 Managing the Screen Session

| Task | Command |
|------|----------|
| **List all screen sessions** | `screen -ls` |
| **Reattach to the vLLM session** | `screen -r vllm` |
| **Detach from the session (keep running)** | `Ctrl + A` then `D` |
| **Terminate the vLLM server and exit screen** | Inside the session: `Ctrl + C`, then `exit` |
| **Force kill the session (from outside)** | `screen -S vllm -X quit` |

---

## 🧪 Verifying the Server

Once running, from the **same machine**:

**Quick verification:**
```bash
curl -s http://127.0.0.1:8000/v1/models -H "Authorization: Bearer dummy"
```

Expected output:
```json
{"object":"list","data":[{"id":"openai/gpt-oss-20b", ... }]}
```

**Comprehensive testing:**
```bash
make test-models    # Test /v1/models endpoint
make test-tools     # Test tool calling functionality
```

**Llama-specific testing:**
```bash
make test-llama-chat        # Test Llama chat completion
make test-llama-tools       # Test Llama tool calling
make test-llama-roundtrip   # Test Llama roundtrip with tools
```

---

## 🔐 SSH Tunnel (optional, from your local machine)

If the server listens only on `127.0.0.1`, use an SSH tunnel for remote access:

```bash
ssh -N -f -L 8001:127.0.0.1:8000 <user>@<remote-ip>
```

Then, connect locally to:
```
http://127.0.0.1:8001/v1
```

To close the tunnel:
```bash
pkill -f "ssh -N -f -L 8001:127.0.0.1:8000"
```

---

## 🧹 Cleanup

To safely shut down everything:

**Option 1: Graceful shutdown (recommended)**
1. Reattach to the screen session: `screen -r vllm`
2. Stop the server with `Ctrl + C`
3. Exit the screen session: `exit`

**Option 2: Force cleanup**
```bash
make stop              # General cleanup
# OR for Llama specifically:
make stop-llama        # Stop Llama server
screen -S vllm -X quit
```

**Verify GPU memory is free:**
```bash
gpustat
```

**Monitor logs:**
```bash
make logs-llama    # Follow Llama server logs in real-time
```

---

**Tip:** You can also automate this workflow with:
```bash
make serve   # inside a screen
make tunnel  # locally to connect
make stop-tunnel
```
