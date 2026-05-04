# ROCm llama.cpp Router Server

Secure, multi-model inference server built on ROCm with llama.cpp router mode.

## Models

| Model | Context | Temp |
|-------|---------|------|
| unsloth/Qwen3.6-27B-GGUF:Q8_0 | 262k | 0.6 |
| unsloth/gemma-4-31B-it-GGUF:Q8_0 | default | 1.0 |
| unsloth/Qwen3.6-35B-A3B-GGUF:Q8_0 | 262k | 0.6 |
| unsloth/gemma-4-26B-A4B-it-GGUF:Q8_0 | default | 1.0 |

## Prerequisites

- ROCm-compatible AMD GPU (gfx908 or gfx1100)
- Docker or Podman installed
- Models pre-downloaded to `~/.cache/huggingface/` (see below)

## Stages

The server progresses through four stages. All stages are present in the code from the start — progression happens by commenting/uncommenting marked sections. See `TEST_PLAYBOOK.md` for detailed verification at each stage.

| Stage | Mode | How to run |
|-------|------|-----------|
| 1 | Interactive Debug | `./run-server.sh` (default) — drops to shell inside container |
| 2 | Script-Initiated Server | Detached container, server started with --keep-alive |
| 3 | Auto-Start Server | Detached container, server starts via Dockerfile CMD |
| 4 | Production Router | Detached container, router mode with models-preset |

## Pre-download Models

Download models before first run so the container can find them without network access:

```bash
# Install Hugging Face tools
pip install huggingface_hub hf_transfer

# Download each model
hf download unsloth/Qwen3.6-27B-GGUF --include "*.gguf"
hf download unsloth/gemma-4-31B-it-GGUF --include "*.gguf"
hf download unsloth/Qwen3.6-35B-A3B-GGUF --include "*.gguf"
hf download unsloth/gemma-4-26B-A4B-it-GGUF --include "*.gguf"
```

## Build

```bash
cd /home/hilton/git/rocm_docker

# Docker
docker build -t llama-cpp-server .

# Podman
podman build -t llama-cpp-server .
```

## Run

```bash
# Default: Stage 1 interactive debug shell
./run-server.sh
```

The script defaults to Stage 1 (interactive debug). See `TEST_PLAYBOOK.md` for stage progression instructions and verification steps.

### Podman

Podman can act as a drop-in replacement for Docker. Either:

**Option A: Use `podman` directly** (edit `run-server.sh` or override):

```bash
# Replace docker with podman in the run command
export RUNTIME=podman
$RUNTIME run -d \
  --name llama-server \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --security-opt no-new-privileges:true \
  --device /dev/kfd \
  --device /dev/dri \
  --network none \
  --mount type=bind,source="$HOME/.cache/huggingface",target=/huggingface \
  --mount type=bind,source="$HOME/models",target=/models,ro \
  llama-cpp-server \
  --models-preset /etc/llama-server/models.ini \
  --host 0.0.0.0 \
  --port 8000
```

**Option B: Use the `podman-docker` compat layer**

```bash
# Install podman-docker (provides 'docker' command that calls podman)
sudo apt install podman-docker

# Then run normally
./run-server.sh
```

## Usage

Once running, the server exposes an OpenAI-compatible API on port 8000.

List available models:
```bash
curl http://localhost:8000/v1/models
```

Chat completion (specify model in the request):
```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "unsloth/Qwen3.6-27B-GGUF:Q8_0",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Manage

```bash
# Stop
docker stop llama-server

# Remove
docker rm llama-server

# Logs
docker logs -f llama-server

# Restart
./run-server.sh
```

## Customize

Edit `models.ini` to change per-model settings or add new models. Rebuild the image after changes:

```bash
docker build -t llama-cpp-server .
```

## Security

This setup follows defense-in-depth principles:
- `--read-only` — immutable container filesystem
- `--network none` — no outbound connections
- `--security-opt no-new-privileges` — no privilege escalation
- `USER nobody` — non-root execution
- Models mounted read-only
- Source tree removed from final image
