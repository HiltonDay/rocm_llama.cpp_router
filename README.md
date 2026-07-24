# ROCm llama.cpp Server

Multi-model inference server running llama.cpp on AMD GPUs via ROCm 7.2.4.

## Stack

- Base image: `rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0`
- llama.cpp: commit `c1304d7b` (latest master)
- GPU targets: gfx908, gfx1100
- Includes: `llama-server`, `llama-bench`

## Models

| Model | Context | Temp |
|-------|---------|------|
| unsloth/Qwen3.6-27B-GGUF:Q8_0 | 262k | 0.6 |
| unsloth/gemma-4-31B-it-GGUF:Q8_0 | 196k | 1.0 |
| unsloth/Qwen3.6-35B-A3B-GGUF:Q8_0 | 262k | 0.6 |
| unsloth/gemma-4-26B-A4B-it-GGUF:Q8_0 | 262k | 1.0 |

## Prerequisites

- AMD GPU (gfx908 or gfx1100)
- Podman or Docker
- Models pre-downloaded to `~/.cache/huggingface/`

## Pre-download Models

```bash
pip install huggingface_hub hf_transfer

hf download unsloth/Qwen3.6-27B-GGUF --include "*.gguf"
hf download unsloth/gemma-4-31B-it-GGUF --include "*.gguf"
hf download unsloth/Qwen3.6-35B-A3B-GGUF --include "*.gguf"
hf download unsloth/gemma-4-26B-A4B-it-GGUF --include "*.gguf"
```

## Build

```bash
podman build -t rocm-llama-cpp:rocm724 .
```

## Usage

### Start server (detached)

```bash
./run-server.sh
```

Runs the llama-server in router mode on port 8000 with the models defined in `models.ini`.

### Stop server

```bash
./stop-server.sh
```

### Interactive shell

```bash
./interactive-server.sh
```

Opens a bash shell inside the container with GPU access. Both `llama-server` and `llama-bench` are on the PATH for manual use.

### API

Once running, the server exposes an OpenAI-compatible API on port 8000.

```bash
# List models
curl http://localhost:8000/v1/models

# Chat completion
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "unsloth/Qwen3.6-27B-GGUF:Q8_0",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Benchmarking

From inside the interactive shell:

```bash
llama-bench -m /tmp/huggingface/hub/models--unsloth--Qwen3.6-27B-GGUF/snapshots/*/Qwen3.6-27B-Q8_0.gguf -ngl 99
```

## Customization

Edit `models.ini` for model configuration. Rebuild after changes.

GPU architecture targets are set via `LLAMACPP_ROCM_ARCH` in the Dockerfile.

## Security

- `--read-only` filesystem (run-server.sh)
- `--security-opt no-new-privileges`
- Non-root execution (llama user)
- HuggingFace cache mounted from host
- Source tree removed from final image
