# vllm-oneport Makefile
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Use local docker-compose binary in project directory
DOCKER_COMPOSE := ./docker-compose
IP?=0.0.0.0

help: ## Show help
	@awk 'BEGIN{FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_.-]+:.*?##/{printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST); echo

install-nvidia: ## Install NVIDIA Container Toolkit (requires sudo)
	@echo "Installing NVIDIA Container Toolkit..."
	@curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
	@curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
		sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
		sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
	@sudo apt update
	@sudo apt install -y nvidia-container-toolkit
	@sudo nvidia-ctk runtime configure --runtime=docker
	@sudo systemctl restart docker
	@echo "NVIDIA Container Toolkit installed successfully!"

deps: ## Check docker compose availability
	@if [ ! -f "$(DOCKER_COMPOSE)" ]; then \
		echo "Installing docker-compose..."; \
		curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$$(uname -s)-$$(uname -m)" -o "$(DOCKER_COMPOSE)"; \
		chmod +x "$(DOCKER_COMPOSE)"; \
	fi
	@$(DOCKER_COMPOSE) --version >/dev/null

init: deps ## Create data dirs and default active env
	@mkdir -p data/hf logs
	@[ -e .env.active ] || ln -sf .env.gptoss20b .env.active
	@echo "Active -> $$(readlink .env.active)"

up: deps ## Start vLLM
	@$(DOCKER_COMPOSE) --env-file .env.active up -d vllm

down: deps ## Stop vLLM
	@$(DOCKER_COMPOSE) --env-file .env.active down

restart: deps ## Restart vLLM
	@$(DOCKER_COMPOSE) --env-file .env.active restart vllm

ps: deps ## Compose ps
	@$(DOCKER_COMPOSE) --env-file .env.active ps

logs: deps ## Tail logs
	@$(DOCKER_COMPOSE) --env-file .env.active logs -f vllm

switch: ## Switch model: make switch MODEL=gptoss|llama70b
	@test -n "$(MODEL)" || (echo "Set MODEL=gptoss|llama70b" && exit 1)
	@if [ "$(MODEL)" = "gptoss" ]; then ln -sf .env.gptoss20b .env.active; \
	elif [ "$(MODEL)" = "llama70b" ]; then ln -sf .env.llama70b_gptq .env.active; \
	else echo "Unknown MODEL=$(MODEL)"; exit 1; fi
	@echo "Active -> $$(readlink .env.active)"
	@$(DOCKER_COMPOSE) --env-file .env.active up -d vllm

set-ip: ## Bind to a specific LAN IP: make set-ip IP=192.168.10.20
	@for f in .env.gptoss20b .env.llama70b_gptq; do \
	  if grep -q '^BIND_IP=' $$f; then sed -i -E "s|^BIND_IP=.*|BIND_IP=$(IP)|" $$f; \
	  else echo "BIND_IP=$(IP)" >> $$f; fi; done
	@echo "Set BIND_IP=$(IP) (restart required)"

set-key: ## Set API key: make set-key KEY=...
	@test -n "$(KEY)" || (echo "Set KEY=..." && exit 1)
	@for f in .env.gptoss20b .env.llama70b_gptq; do \
	  if grep -q '^VLLM_API_KEY=' $$f; then sed -i -E "s|^VLLM_API_KEY=.*|VLLM_API_KEY=$(KEY)|" $$f; \
	  else echo "VLLM_API_KEY=$(KEY)" >> $$f; fi; done
	@echo "API key updated"

curl: ## Show /v1/models
	@./scripts/test.sh models

test: ## Smoke test: /v1/models and /v1/chat/completions
	@./scripts/test.sh smoke

install: deps ## Install to /opt/vllm + systemd unit (root)
	@if [ "$$(id -u)" -ne 0 ]; then echo "Run as root: sudo make install"; exit 1; fi
	@echo "Installing vLLM to /opt/vllm..."
	@mkdir -p /opt/vllm
	@echo "Copying files to /opt/vllm (this may take a moment)..."
	@rsync -a --delete ./ /opt/vllm/
	@echo "Setting up docker-compose..."
	@chmod +x /opt/vllm/docker-compose
	@echo "Initializing directories and environment..."
	@cd /opt/vllm && make init
	@echo "Installing systemd service..."
	@install -D -m 0644 systemd/vllm.service /etc/systemd/system/vllm.service
	@systemctl daemon-reload
	@echo "Starting vLLM service..."
	@systemctl enable vllm
	@systemctl start vllm
	@systemctl disable vllm
	@echo "✅ Installed to /opt/vllm and started systemd unit 'vllm' (auto-start disabled)"

uninstall: ## Remove systemd unit and /opt/vllm (root)
	@if [ "$$(id -u)" -ne 0 ]; then echo "Run as root: sudo make uninstall"; exit 1; fi
	@systemctl disable --now vllm || true
	@rm -f /etc/systemd/system/vllm.service
	@systemctl daemon-reload
	@rm -rf /opt/vllm
	@echo "Uninstalled vllm service and /opt/vllm"

status: ## systemd status
	@systemctl status vllm || true
