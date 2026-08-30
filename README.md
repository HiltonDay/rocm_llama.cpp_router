# ROCm llama.cpp container

This directory builds and runs `llama-server` and `llama-bench` for AMD GPUs through ROCm HIP. The current image is based on ROCm 7.14 and compiles llama.cpp commit `9723942adc518b43c4b95dc4dce6906903eb5e09` for `gfx908`, `gfx1100`, and `gfx1201`.

The operational guide uses `unsloth/Qwen3.5-2B-GGUF` for small smoke tests. The router configuration contains larger models for normal use; loading those models needs the available VRAM and can take longer.

## Quick start: interactive Qwen3.8-27B

Run these commands from `rocm_docker/`. The first command starts a detached interactive container using the persistent `rocm-llama-home` volume. The second opens a Bash console in that container. Run the third command inside the container:

```bash
# 1. Launch the container in the background.
./interactive-server.sh --detach

# 2. Open a Bash console on the running container.
docker exec -it --user llama rocm-llama-interactive /bin/bash

# 3. Inside the container, launch the requested model.
llama-server \
  --hf-repo unsloth/Qwen3.8-27B-GGUF \
  --host 127.0.0.1 \
  --port 8000 \
  --ctx-size 4096 \
  --flash-attn on \
  -ngl 99
```

The model server is then available from the host at `http://127.0.0.1:8000`. Stop the foreground server with `Ctrl-C`, exit Bash, then remove the detached container cleanly:

```bash
docker stop --time 30 rocm-llama-interactive
```

The named volume `rocm-llama-home` persists `/home/llama`, including `.bash_history`, between interactive sessions. The default `./interactive-server.sh` command combines steps 1 and 2 by launching directly into Bash.

## Quick start: Qwen3.8-27B multi-GPU modes

The GPU indices below use the validated ROCm enumeration: physical device 0 is an R9700, device 1 is the MI100, device 2 is the RX 7900 XTX, and device 3 is the second R9700. `HIP_VISIBLE_DEVICES` remaps the selected physical devices to logical indices inside the container.

### Two R9700s: tensor-parallel mode, 256k context

Use physical devices 0 and 3. Inside the container they become logical GPUs 0 and 1. The 256k configuration uses 16-bit FP16 KV cache:

```bash
# Host: start an interactive container with only the two R9700s visible.
HIP_VISIBLE_DEVICES=0,3 ./interactive-server.sh --detach

# Host: open a Bash console.
docker exec -it --user llama rocm-llama-interactive /bin/bash

# Container: start Qwen3.8-27B with tensor parallelism and 256k context.
llama-server \
  --hf-repo unsloth/Qwen3.8-27B-GGUF \
  --split-mode tensor \
  --tensor-split 1,1 \
  --ctx-size 262144 \
  --flash-attn on \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --host 127.0.0.1 \
  --port 8000 \
  -ngl all
```

Native MTP is optional. To enable the embedded MTP branch with draft depth 3, add these parameters to the command above:

```text
--spec-type draft-mtp
--spec-draft-n-max 3
--spec-draft-type-k f16
--spec-draft-type-v f16
--parallel 1
--no-cache-prompt
```

The optional MTP parameters use the same 16-bit FP16 KV cache at 256k context. Q8 KV can reduce memory use if FP16 KV does not fit; use `--cache-type-k q8_0 --cache-type-v q8_0` and matching `--spec-draft-type-k q8_0 --spec-draft-type-v q8_0` as the fallback.

### RX 7900 XTX and MI100: layer-split mode, 200k context

Use physical devices 1 and 2. They become logical GPUs 0 and 1. Row splitting was tested but is not supported by the MI100 path in this image (`device ROCm0 does not support split buffers`), so this workflow uses the compatible layer split:

```bash
# Host: start an interactive container with only the MI100 and RX 7900 XTX visible.
HIP_VISIBLE_DEVICES=1,2 ./interactive-server.sh --detach

# Host: open a Bash console.
docker exec -it --user llama rocm-llama-interactive /bin/bash

# Container: start Qwen3.8-27B with layer splitting and 200k context.
llama-server \
  --hf-repo unsloth/Qwen3.8-27B-GGUF \
  --split-mode layer \
  --tensor-split 1,1 \
  --ctx-size 204800 \
  --flash-attn on \
  --host 127.0.0.1 \
  --port 8000 \
  -ngl all
```

Stop either session by pressing `Ctrl-C` in the server console, exiting Bash, and running:

```bash
docker stop --time 30 rocm-llama-interactive
```

## Quick start: two networked Qwen3.8-27B containers

Run one model server in each of two containers, with the validated GPU pairs assigned independently. Both containers join the same user-defined Docker network. The llama-server port remains `8000` inside each container; `HOST_PORT` publishes distinct host loopback ports for host clients. Other Docker containers on `rocm-llama-net` should use the container names and internal port `8000`.

Create the shared network once:

```bash
docker network create rocm-llama-net
```

### Container 1: two R9700s, tensor split

Physical GPUs 0 and 3 are remapped to logical GPUs 0 and 1 inside this container:

```bash
# Host terminal 1.
IMAGE=rocm-llama-cpp:rocm714 \
HOME_VOLUME=rocm-llama-home-r9700-pair \
CONTAINER_NAME=rocm-llama-r9700-pair \
NETWORK=rocm-llama-net \
HOST_PORT=8001 \
HIP_VISIBLE_DEVICES=0,3 \
./interactive-server.sh --detach

docker exec -it --user llama rocm-llama-r9700-pair /bin/bash
```

Inside the first container:

```bash
llama-server \
  --hf-repo unsloth/Qwen3.8-27B-GGUF \
  --split-mode tensor \
  --tensor-split 1,1 \
  --ctx-size 262144 \
  --flash-attn on \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --host 0.0.0.0 \
  --port 8000 \
  -ngl all
```

### Container 2: MI100 and RX 7900 XTX, layer split

Physical GPUs 1 and 2 are remapped to logical GPUs 0 and 1 inside this container:

```bash
# Host terminal 2.
IMAGE=rocm-llama-cpp:rocm714 \
HOME_VOLUME=rocm-llama-home-mixed-pair \
CONTAINER_NAME=rocm-llama-mixed-pair \
NETWORK=rocm-llama-net \
HOST_PORT=8002 \
HIP_VISIBLE_DEVICES=1,2 \
./interactive-server.sh --detach

docker exec -it --user llama rocm-llama-mixed-pair /bin/bash
```

Inside the second container:

```bash
llama-server \
  --hf-repo unsloth/Qwen3.8-27B-GGUF \
  --split-mode layer \
  --tensor-split 1,1 \
  --ctx-size 204800 \
  --flash-attn on \
  --host 0.0.0.0 \
  --port 8000 \
  -ngl all
```

Host clients use `http://127.0.0.1:8001` for the two-R9700 server and `http://127.0.0.1:8002` for the MI100/RX 7900 XTX server. A peer container must join `rocm-llama-net` and can use these base URLs instead:

```text
http://rocm-llama-r9700-pair:8000
http://rocm-llama-mixed-pair:8000
```

For example, start a peer with `--network rocm-llama-net`, or attach an existing container with `docker network connect rocm-llama-net <container>`. The `--host 0.0.0.0` setting is required for access through the Docker bridge; do not use the `127.0.0.1` setting from the single-container quick start.

Stop both servers with `Ctrl-C`, exit each Bash shell, then remove the containers and network:

```bash
docker stop --time 30 rocm-llama-r9700-pair rocm-llama-mixed-pair
docker network rm rocm-llama-net
```

The named home volumes remain unless explicitly removed. Remove `rocm-llama-home-r9700-pair` and `rocm-llama-home-mixed-pair` only if their persisted shell history is no longer needed.

## Quick start

Build a persistent local image:

```bash
docker build -t rocm-llama-cpp:rocm714 .
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
| Base image | `rocm/pytorch:rocm7.14_ubuntu24.04_py3.12_pytorch_release_2.12.0` |
| llama.cpp | `9723942adc518b43c4b95dc4dce6906903eb5e09` |
| ROCm targets | `gfx908`, `gfx1100`, `gfx1201` |
| Binaries | `/usr/local/bin/llama/llama-server`, `/usr/local/bin/llama/llama-bench` |
| Runtime user | `llama`, in `video` and `render` groups |
| Default cache | `HF_HOME=/home/llama/.cache/huggingface` |
| Interactive home | `rocm-llama-home:/home/llama` |
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
IMAGE=rocm-llama-cpp:rocm714-test ./interactive-server.sh

# Persist interactive home state in a different named volume.
HOME_VOLUME=rocm-llama-home-test ./interactive-server.sh

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
