# vLLM Server Management Guide

This document explains how to start, manage, and stop the **vLLM OpenAI-compatible API server** running inside a `screen` session.

---

## 🧠 Overview

The vLLM server provides an OpenAI-compatible API endpoint, typically used for local or remote inference (e.g., `openai/gpt-oss-20b`).

We use **GNU Screen** to keep the server running in the background, even after SSH disconnection.

### GPU memory requirements excl KV cache
70B model INT4 quantization

- weights: 35G
- quant overhead: ~2G

---

## 🧮 Memory Consumption Calculation

Understanding how to calculate memory usage for different context lengths is crucial for optimizing your vLLM server configuration.

### Memory Components

**Total GPU Memory = Model Memory + Context Memory + Overhead**

#### 1. Model Memory
- **GPT-OSS 20B**: ~20GB (with quantization)
- **Llama 70B INT4**: ~35GB + 2GB overhead = ~37GB
- **Llama 8B**: ~8GB

#### 2. Context Memory (KV Cache)
The context memory scales with the number of tokens and model architecture:

```
Context Memory = Tokens × Layers × 2 bytes × 2 (K + V cache)
```

**For GPT-OSS 20B:**
- **Layers**: ~40-50 layers
- **Memory per token**: ~80-100 bytes per token
- **Formula**: `Tokens × 100 bytes`

**Examples:**
- **4K tokens**: 4,096 × 100 bytes = ~400MB per GPU
- **8K tokens**: 8,192 × 100 bytes = ~800MB per GPU  
- **16K tokens**: 16,384 × 100 bytes = ~1.6GB per GPU
- **32K tokens**: 32,768 × 100 bytes = ~3.2GB per GPU

#### 3. Memory Overhead
- **CUDA overhead**: ~1-2GB
- **PyTorch overhead**: ~500MB-1GB
- **System overhead**: ~500MB

### Practical Examples

#### Example 1: GPT-OSS 20B on 2×RTX 4090 (48GB total)
```
Model Memory:     20GB
Context (32K):    6.4GB  (3.2GB per GPU)
Overhead:         2GB
Total:           28.4GB  (fits comfortably in 48GB)
```

#### Example 2: Llama 70B INT4 on 2×RTX 4090
```
Model Memory:     37GB
Context (8K):     1.6GB  (800MB per GPU)
Overhead:         2GB
Total:           40.6GB  (tight fit, may need smaller context)
```

#### Example 3: GPT-OSS 20B on 2×A6000 (96GB total)
```
Model Memory:     20GB
Context (64K):   12.8GB  (6.4GB per GPU)
Overhead:         2GB
Total:           34.8GB  (excellent headroom in 96GB)
```

#### Example 4: Llama 70B INT4 on 1×A6000 (48GB)
```
Model Memory:     37GB
Context (16K):    3.2GB
Overhead:         2GB
Total:           42.2GB  (comfortable fit in 48GB)
```

### Context Length Recommendations

| GPU Setup | Model | Recommended Context | Max Context |
|-----------|-------|-------------------|-------------|
| 2×RTX 4090 (48GB) | GPT-OSS 20B | 16K-32K tokens | 32K+ tokens |
| 2×RTX 4090 (48GB) | Llama 70B INT4 | 4K-8K tokens | 8K-16K tokens |
| 1×RTX 4090 (24GB) | GPT-OSS 20B | 8K-16K tokens | 16K tokens |
| 1×RTX 4090 (24GB) | Llama 8B | 16K-32K tokens | 32K+ tokens |
| 2×A6000 (96GB) | GPT-OSS 20B | 32K-64K tokens | 64K+ tokens |
| 2×A6000 (96GB) | Llama 70B INT4 | 16K-32K tokens | 32K+ tokens |
| 1×A6000 (48GB) | GPT-OSS 20B | 16K-32K tokens | 32K+ tokens |
| 1×A6000 (48GB) | Llama 70B INT4 | 8K-16K tokens | 16K-32K tokens |

### Memory Optimization Tips

1. **Reduce context length** if you get OOM errors
2. **Use `--enforce-eager`** to disable CUDA graphs (saves memory)
3. **Enable `--swap-space`** for additional memory when needed
4. **Monitor with `gpustat`** to see actual memory usage
5. **Use tensor parallelism** to distribute memory across GPUs

### Quick Memory Check
```bash
# Check current GPU memory usage
gpustat

# Monitor during server startup
watch -n 1 gpustat
```

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
