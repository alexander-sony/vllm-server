# vLLM Makefile — run GPT-OSS:20B locally (and friends)
# Usage:
#   make help
#   make install
#   make serve              # single-GPU (e.g., 4090 24GB)
#   make serve-tp2          # multi-GPU (e.g., 2× RTX 6000 Ada)
#   make serve-8b           # lightweight local dev model
#   make test               # quick OpenAI-compatible smoke tests
#   make ssh-tunnel REMOTE=user@host  # tunnel to a remote vLLM
#   make stop               # kill a local vLLM on $(PORT)

# --- Load overrides from .env (optional) ---------------------------------------
-include .env

# --- Paths ---------------------------------------------------------------------
VENV        ?= .venv
PY          := $(VENV)/bin/python
PIP         := $(VENV)/bin/pip
VLLM        := $(VENV)/bin/vllm
CURL        := curl -s
UV          ?= uv

# --- Defaults (override in .env or on the CLI) ---------------------------------
MODEL_ID    ?= openai/gpt-oss-20b
PORT        ?= 8000
HOST        ?= 127.0.0.1                # use 0.0.0.0 to listen on all interfaces
TP          ?= 1                        # tensor parallel size
GPU_UTIL    ?= 0.90
MAX_LEN     ?= 8192
NUM_SEQS    ?= 4
CUDA_DEVICES?= 0                        # which GPUs to use (comma-separated)
AUTH_TOKEN  ?= dummy                    # vLLM accepts any non-empty Bearer

# A lean local dev model for laptops (7B/8B class)
DEV_MODEL_ID?= meta-llama/Meta-Llama-3.1-8B-Instruct

# --- Help ----------------------------------------------------------------------
.PHONY: help
help:
	@echo "Targets:"
	@echo "  make install           # install vLLM into $(VENV)"
	@echo "  make serve             # serve $(MODEL_ID) @ $(HOST):$(PORT) (TP=$(TP))"
	@echo "  make serve-tp2         # serve $(MODEL_ID) with tensor-parallel=2"
	@echo "  make serve-8b          # serve $(DEV_MODEL_ID) for lightweight dev"
	@echo "  make test              # /v1/models and simple chat completion"
	@echo "  make ssh-tunnel REMOTE=user@host    # local port -> remote"
	@echo "  make stop              # kill process listening on $(PORT)"
	@echo ""
	@echo "Override via CLI or .env (see .env.example)."

# --- Setup ---------------------------------------------------------------------
.PHONY: install
install:
	@echo "Installing vLLM into $(VENV) ..."
	$(UV) pip install -U pip wheel
	$(UV) pip install -U vllm "huggingface_hub[cli]"
	@echo "Done."

# --- Serve: main 20B model -----------------------------------------------------
.PHONY: serve
serve:
	@echo "Serving $(MODEL_ID) on $(HOST):$(PORT) (TP=$(TP)) ..."
	@CUDA_VISIBLE_DEVICES=$(CUDA_DEVICES) \
	PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
	$(VLLM) serve $(MODEL_ID) \
	  --host $(HOST) --port $(PORT) \
	  --tensor-parallel-size $(TP) \
	  --gpu-memory-utilization $(GPU_UTIL) \
	  --max-model-len $(MAX_LEN) \
	  --max-num-seqs $(NUM_SEQS) \
      --tool-call-parser openai \
	  --enable-auto-tool-choice

# Convenience: 2-GPU tensor parallel on powerful boxes (e.g., 2× 48GB)
.PHONY: serve-tp2
serve-tp2:
	@$(MAKE) serve TP=2 CUDA_DEVICES=0,1 GPU_UTIL=$(GPU_UTIL) MAX_LEN=$(MAX_LEN) NUM_SEQS=$(NUM_SEQS)

# Lightweight local dev model (good for 8–12 GB GPUs)
.PHONY: serve-8b
serve-8b:
	@echo "Serving $(DEV_MODEL_ID) on $(HOST):$(PORT) ..."
	@CUDA_VISIBLE_DEVICES=$(CUDA_DEVICES) \
	PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
	$(VLLM) serve $(DEV_MODEL_ID) \
	  --host $(HOST) --port $(PORT) \
	  --tensor-parallel-size 1 \
	  --gpu-memory-utilization 0.90 \
	  --max-model-len 4096 \
	  --max-num-seqs 4

# --- Tests ---------------------------------------------------------------------
.PHONY: test-models test-tools
test-models:
	BASE_URL="http://$(strip $(HOST)):$(strip $(PORT))/v1" \
	AUTH_TOKEN="$(AUTH_TOKEN)" \
	scripts/test_models.sh

test-tools:
	BASE_URL="http://$(strip $(HOST)):$(strip $(PORT))/v1" \
	MODEL_ID="$(MODEL_ID)" \
	AUTH_TOKEN="$(strip $(AUTH_TOKEN))" \
	scripts/test_tools.sh

# --- Remote access helpers -----------------------------------------------------
# SSH tunnel: forwards local $(PORT) -> remote $(PORT)
.PHONY: ssh-tunnel
ssh-tunnel:
ifndef REMOTE
	$(error Usage: make ssh-tunnel REMOTE=user@host)
endif
	@echo "Tunneling localhost:$(PORT) -> $(REMOTE):$(PORT). Ctrl-C to close."
	@ssh -N -L $(PORT):127.0.0.1:$(PORT) $(REMOTE)

# --- Stop server ---------------------------------------------------------------
.PHONY: stop clean-gpu
stop:
	@PORT=$(PORT) scripts/clean_gpu.sh

clean-gpu:
	@PORT=$(PORT) scripts/clean_gpu.sh

