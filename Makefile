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
PORT        ?= 8000
HOST        ?= 127.0.0.1                # use 0.0.0.0 to listen on all interfaces
TP          ?= 1                        # tensor parallel size
GPU_UTIL    ?= 0.90
MAX_LEN     ?= 8192
NUM_SEQS    ?= 4
CUDA_DEVICES?= 0                        # which GPUs to use (comma-separated)
AUTH_TOKEN  ?= dummy                    # vLLM accepts any non-empty Bearer
LOG_DIR     ?= logs

# ---- Llama single-GPU targets -------------------------------------------------
MODEL_LLAMA8B ?= meta-llama/Meta-Llama-3.1-8B-Instruct

# ---- GPT-OSS 20B targets -----------------------------------------------------
MODEL_GPT_OSS_20B ?= openai/gpt-oss-20b

# ---- Llama 3.1 70B GPTQ INT4 targets -------------------------------------------------
MODEL_LLAMA70B_GPTQ ?= hugging-quants/Meta-Llama-3.1-70B-Instruct-GPTQ-INT4

# --- Setup ---------------------------------------------------------------------
.PHONY: install
install:
	@echo "Installing vLLM into $(VENV) ..."
	$(UV) pip install -U pip wheel
	$(UV) pip install -U vllm "huggingface_hub[cli]"
	@echo "Done."

AUTO_TOOLS          ?= --enable-auto-tool-choice
PARSER_LLAMA        ?= --tool-call-parser llama3_json

# --- Serve: Llama 3.1 70B GPTQ INT4 on 2× A6000 ---
.PHONY: serve-llama70b-gptq-tp2
serve-llama70b-gptq-tp2:
	@mkdir -p $(LOG_DIR)
	HUGGING_FACE_HUB_TOKEN="$(HF_TOKEN)" \
	# Some setting that allows running on a multi-GPU A6000
	NCCL_P2P_DISABLE=0 \
	NCCL_P2P_LEVEL=NVL \
	NCCL_SHM_DISABLE=0 \
	CUDA_VISIBLE_DEVICES=0,1 vllm serve "$(MODEL_LLAMA70B_GPTQ)" \
	--tensor-parallel-size 2 \
	--quantization gptq_marlin \
	--enable-auto-tool-choice \
	--tool-call-parser llama3_json \
	--dtype auto \
	--max-model-len 8192 \
	--max-num-seqs 96 \
	--gpu-memory-utilization 0.95 \
	--swap-space 16 \
	--enforce-eager \
	--disable-custom-all-reduce \
	--port $(PORT) | tee "$(LOG_DIR)/llama70b.gptqmarlin.$(PORT).log"

.PHONY: serve-llama70b-gptq-tp1
serve-llama70b-gptq-tp1:
	@mkdir -p $(LOG_DIR)
	HUGGING_FACE_HUB_TOKEN="$(HF_TOKEN)" \
	CUDA_VISIBLE_DEVICES=0 vllm serve "$(MODEL_LLAMA70B_GPTQ)" \
	--tensor-parallel-size 1 \
	--quantization gptq_marlin \
	--enable-auto-tool-choice \
	--tool-call-parser llama3_json \
	--dtype auto \
	--max-model-len 3072 \
	--max-num-seqs 16 \
	--gpu-memory-utilization 0.92 \
	--swap-space 16 \
	--enforce-eager \
	--disable-custom-all-reduce \
	--port $(PORT) | tee "$(LOG_DIR)/llama70b.gptqmarlin.$(PORT).log"

# --- Tests ---
list-llama70b-gptq:
	BASE_URL="http://$(strip $(HOST)):$(strip $(PORT))/v1" \
	AUTH_TOKEN="dummy" \
	$(UV) run scripts/test_models.py models

test-llama70b-gptq-chat:
	BASE_URL="http://$(strip $(HOST)):$(strip $(PORT))/v1" \
	AUTH_TOKEN="dummy" \
	$(UV) run scripts/test_models.py chat --model-id $(MODEL_LLAMA70B_GPTQ) --prompt "Say hello in 5 words." --max-tokens 16

test-llama70b-gptq-tools:
	BASE_URL="http://$(strip $(HOST)):$(strip $(PORT))/v1" \
	AUTH_TOKEN="dummy" \
	$(UV) run scripts/test_models.py tools --model-id $(MODEL_LLAMA70B_GPTQ) --prompt "Call get_time."

test-llama70b-gptq-roundtrip:
	BASE_URL="http://$(strip $(HOST)):$(strip $(PORT))/v1" \
	AUTH_TOKEN="dummy" \
	$(UV) run scripts/test_models.py roundtrip --model-id $(MODEL_LLAMA70B_GPTQ)

# ---- Llama 3.1 8B Instruct targets -------------------------------------------------
.PHONY: serve-llama8b test-llama8b logs-llama stop-llama

serve-llama8b:
	@mkdir -p $(LOG_DIR)
	CUDA_VISIBLE_DEVICES=$(CUDA_DEVICES)  \
	$(VLLM) serve "$(MODEL_LLAMA8B)" \
	  --dtype auto \
	  --max-model-len 8192 \
	  --gpu-memory-utilization 0.92 \
	  --max-num-seqs 512 \
	  --tool-call-parser llama3_json \
	  --enable-auto-tool-choice \
	  --port $(PORT) 2>&1 | tee "$(LOG_DIR)/llama8b.$(PORT).log"

# Minimal OpenAI-compatible smoke test
test-llama-chat:
	OPENAI_BASE_URL="http://$(strip $(HOST)):$(strip $(PORT))/v1" \
	OPENAI_API_KEY="$(strip $(AUTH_TOKEN))" \
	$(UV) run scripts/test_models.py --alias llama8b chat --prompt "Say hello in 5 words." --max-tokens 16

test-llama-tools:
	OPENAI_BASE_URL="http://$(strip $(HOST)):$(strip $(PORT))/v1" \
	OPENAI_API_KEY="$(strip $(AUTH_TOKEN))" \
	$(UV) run scripts/test_models.py --alias llama8b tools --prompt "Call get_time."

test-llama-roundtrip:
	OPENAI_BASE_URL="http://$(strip $(HOST)):$(strip $(PORT))/v1" \
	OPENAI_API_KEY="$(strip $(AUTH_TOKEN))" \
	$(UV) run scripts/test_models.py --alias llama8b roundtrip --prompt "What time is it? Use the tool."

# Follow logs for this run
logs-llama:
	@ls -1t $(LOG_DIR)/llama8b.$(PORT).log 2>/dev/null | head -n1 | xargs tail -n +1 -f

# Stop helper (reuses your clean script if you have one)
stop-llama:
	@pkill -f "vllm serve .*$(MODEL_LLAMA8B).*--port $(PORT)" || true

# --- Serve: GPT-OSS 20B model -----------------------------------------------------
.PHONY: serve-gpt-oss-20b
serve-gpt-oss-20b:
	@mkdir -p $(LOG_DIR)
	@echo "Serving $(MODEL_GPT_OSS_20B) on $(HOST):$(PORT) (TP=$(TP)) ..."
	@CUDA_VISIBLE_DEVICES=$(CUDA_DEVICES) \
	PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
	$(VLLM) serve $(MODEL_GPT_OSS_20B) \
	  --host $(HOST) --port $(PORT) \
	  --tensor-parallel-size $(TP) \
	  --gpu-memory-utilization $(GPU_UTIL) \
	  --max-model-len $(MAX_LEN) \
	  --max-num-seqs $(NUM_SEQS) \
      --tool-call-parser openai \
	  --enable-auto-tool-choice 2>&1 | tee "$(LOG_DIR)/$(MODEL_GPT_OSS_20B).$(PORT).log"

# --- Tests ---------------------------------------------------------------------
.PHONY: test-models test-tools
test-models:
	BASE_URL="http://$(strip $(HOST)):$(strip $(PORT))/v1" \
	AUTH_TOKEN="$(AUTH_TOKEN)" \
	scripts/test_models.sh

test-tools:
	BASE_URL="http://$(strip $(HOST)):$(strip $(PORT))/v1" \
	MODEL_ID="$(MODEL_GPT_OSS_20B)" \
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

