# ROCm llama.cpp container

This directory builds and runs `llama-server` and `llama-bench` for AMD GPUs through ROCm HIP. The current image is based on ROCm 7.2.4 and compiles llama.cpp commit `b10106` for `gfx908`, `gfx1100`, and `gfx1201`.

The operational guide uses `unsloth/Qwen3.5-2B-GGUF` for small smoke tests. The router configuration contains larger models for normal use; loading those models needs the available VRAM and can take longer.

## Quick start

Build a persistent local image:

```bash
docker build -t rocm-llama-cpp:rocm724 .
```

Open an interactive shell with GPU access:

```bash
./interactive-server.sh
```

Start the configured model router in the background:

```bash
./run-server.sh
```

Stop the detached router gracefully:

```bash
./stop-server.sh
```

For the complete procedures and test cases, read [the operations guide](docs/OPERATIONS.md).

## What is in the image

| Component | Current value |
| --- | --- |
| Base image | `rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0` |
| llama.cpp | `b10106` |
| ROCm targets | `gfx908`, `gfx1100`, `gfx1201` |
| Binaries | `/usr/local/bin/llama/llama-server`, `/usr/local/bin/llama/llama-bench` |
| Runtime user | `llama`, in `video` and `render` groups |
| Default cache | `HF_HOME=/home/llama/.cache/huggingface` |
| Router port | `8000` |

The image also contains `huggingface_hub` and `hf_transfer`. The source checkout is removed after compilation.

## Models

`models.ini` is copied into the image at `/etc/llama-server/models.ini` and is used by the detached router. Its section names are the model IDs clients send in API requests. The current entries are:

- `unsloth/Qwen3.6-27B-GGUF:Q8_0`
- `unsloth/gemma-4-31B-it-GGUF:Q8_0`
- `unsloth/Qwen3.6-35B-A3B-GGUF:Q8_0`
- `unsloth/gemma-4-26B-A4B-it-GGUF:Q8_0`

For a small direct smoke test, the operations guide uses `unsloth/Qwen3.5-2B-GGUF`. Direct model loading uses `--hf-repo`; router entries use `hf =` in `models.ini`.

The host cache must contain the model files before a detached router run. The small test model can be downloaded with the Hugging Face CLI:

```bash
hf download unsloth/Qwen3.5-2B-GGUF --include '*.gguf'
```

## Repository structure

```text
rocm_docker/
├── Dockerfile                 # ROCm base, llama.cpp build, runtime image
├── entrypoint.sh              # Cache setup and gosu privilege drop
├── interactive-server.sh      # Temporary interactive Bash container
├── run-server.sh              # Detached models.ini router
├── stop-server.sh             # Graceful stop for rocm-llama
├── models.ini                 # Router model IDs and per-model settings
├── README.md                  # This overview
├── TEST_PLAYBOOK.md           # Link to the authoritative workflow tests
├── docs/
│   ├── OPERATIONS.md          # Build, run, stop, version, bench, GPU tests
│   └── hardware-log.md        # Hardware and benchmark notes
├── specs/                     # Kiro requirements, design, and task records
├── agent_work/                # Earlier implementation work records
├── chats/                     # Archived agent sessions
├── .dockerignore              # Build-context exclusions
└── LICENSE                    # Project license
```

The Markdown files are documentation for the host repository. `.dockerignore` excludes them from the image build context; the image only receives the files explicitly copied by the Dockerfile.

## Configuration

The launcher scripts accept these environment variables:

```bash
# Select a different locally built image.
IMAGE=rocm-llama-cpp:rocm724-test ./interactive-server.sh

# Limit ROCm to the indices reported by llama-bench --list-devices.
HIP_VISIBLE_DEVICES=2,3 ./interactive-server.sh
```

`HIP_VISIBLE_DEVICES` uses ROCm enumeration order. It does not use PCI slot names, and the example `2,3` is not universal. See [GPU selection in the operations guide](docs/OPERATIONS.md#6-select-specific-gpus).

## API

The detached router uses host networking and the Dockerfile CMD currently binds `0.0.0.0:8000`. Treat that as a network service and restrict access with host firewall rules or change the CMD to bind `127.0.0.1` before exposing the machine to an untrusted network.

```bash
curl --fail http://127.0.0.1:8000/v1/models
```

The direct interactive smoke test binds to `127.0.0.1:8000`:

```bash
curl --fail http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"<model-id-from-v1-models>","messages":[{"role":"user","content":"Reply with one sentence."}],"max_tokens":64}'
```

## Related documentation

- [Operations guide](docs/OPERATIONS.md): all requested procedures and their test cases.
- [Test playbook](TEST_PLAYBOOK.md): stable link to the operations tests.
- [Hardware log](docs/hardware-log.md): GPU inventory and recorded benchmark notes.
- [Router requirements](specs/rocm-router-improvements/requirements.md): acceptance criteria for the router work.
- [Router design](specs/rocm-router-improvements/design.md): implementation decisions and constraints.
