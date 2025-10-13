# vllm-server
Single-folder, **one-port** vLLM server you can switch between two models (no parallel run).

## Features
- OpenAI-compatible `/v1/*` over LAN (bind IP configurable).
- One Docker Compose service, one port (default 8000).
- Switch models by symlink: `.env.active` → `.env.gptoss20b` or `.env.llama70b_gptq`.
- `make up/down/switch/test/install` and a systemd unit.

## Quick start (dev)
```bash
git clone <this-repo> vllm-server && cd vllm-server
make init
# Copy example files
cp .env.gptoss20b.example .env.gptoss20b
cp .env.llama70b_gptq.example .env.llama70b_gptq
ln -sf .env.gptoss20b .env.active
# set your API key
make set-key KEY=change-me
# pick model and start
make switch MODEL=gptoss && make up
# test
make test
```

## LAN bind
Default publishes on `0.0.0.0:8000`. To bind to a LAN IP:
```bash
make set-ip IP=192.168.10.20
make up
```

## Install as a service (root)
```bash
sudo make install        # copies to /opt/vllm and installs systemd unit
sudo systemctl status vllm
# switch model later
sudo make -C /opt/vllm switch MODEL=llama70b
sudo systemctl restart vllm
```

**Note**: The service starts immediately after installation but does NOT auto-start on boot by default. To enable auto-start:
```bash
sudo systemctl enable vllm
```
To manage the service manually:
```bash
sudo systemctl start vllm      # start service
sudo systemctl stop vllm       # stop service
sudo systemctl restart vllm    # restart service
sudo systemctl status vllm    # check service status
sudo systemctl enable vllm     # enable auto-start on boot
sudo systemctl disable vllm    # disable auto-start on boot
```

## Testing the service
After installation, test from another machine:
```bash
# Test from another machine (replace SERVER_IP with actual IP)
curl -H "Authorization: Bearer dummy" http://SERVER_IP:8000/v1/models
```

**Note**: The model may take time to load initially. Check service logs:
```bash
sudo make -C /opt/vllm logs    # view service logs
```

When the model is ready, you'll see in the logs:
```
(APIServer pid=1) INFO:     Application startup complete.
```

## Files
- `docker-compose.yml` – single service `vllm`.
- `.env.gptoss20b` / `.env.llama70b_gptq` – model configs (same port).
- `.env.active` – symlink to the active env file.
- `Makefile` – dev/test/run/install helpers.
- `scripts/test.sh` – smoke test for `/v1/models` and `/v1/chat/completions`.
- `systemd/vllm.service` – unit file referencing this folder.
```

