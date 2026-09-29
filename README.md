# ROCm llama.cpp container

This directory builds and runs `llama-server` and `llama-bench` for AMD GPUs through ROCm HIP. The preserved control image `rocm-llama-cpp:rocm714` was built from llama.cpp commit `9723942adc518b43c4b95dc4dce6906903eb5e09`. The RDNA experiment uses a separate image tag and applies the pinned `llama-cpp-rdna-boosts` delivery to its verified llama.cpp baseline `0eadefebd`.

The operational guide uses `unsloth/Qwen3.5-2B-GGUF` for small smoke tests; it is no longer kept in the local cache and streams down on first use. The router configuration contains larger models for normal use; loading those models needs the available VRAM and can take longer.

## Quick start: interactive Qwen3.8-27B

Run these commands from `rocm_docker/`. The first command starts a detached interactive container using the persistent `rocm-llama-home` volume. The second opens a Bash console in that container. Run the third command inside the container:

```bash
# 1. Launch the container in the background (cards 1,2; cards 0,3 are reserved for vLLM).
HIP_VISIBLE_DEVICES=1,2 ./interactive-server.sh --detach

# 2. Open a Bash console on the running container.
docker exec -it --user llama rocm-llama-interactive /bin/bash

# 3. Inside the container, launch the requested model.
llama-server \
  --hf-repo unsloth/Qwen3.8-27B-GGUF \
  --host 127.0.0.1 \
  --port 8000 \
  --ctx-size 4096 \
  --flash-attn on \
  -ngl all
```

The model server is then available from the host at `http://127.0.0.1:8000`. Stop the foreground server with `Ctrl-C`, exit Bash, then remove the detached container cleanly:

```bash
docker stop --time 30 rocm-llama-interactive
```

The named volume `rocm-llama-home` persists `/home/llama`, including `.bash_history`, between interactive sessions. The default `./interactive-server.sh` command combines steps 1 and 2 by launching directly into Bash.

## Quick start: Qwen3.8-27B multi-GPU modes

The GPU indices below use the validated ROCm enumeration: physical device 0 is an R9700, device 1 is the MI100, device 2 is the RX 7900 XTX, and device 3 is the second R9700. `HIP_VISIBLE_DEVICES` remaps the selected physical devices to logical indices inside the container. **Cards 0 and 3 are reserved for vLLM; llama.cpp work defaults to the MI100 + RX 7900 XTX pair (cards 1, 2).**

### Primary: MI100 and RX 7900 XTX, tensor mode, 256k context with MTP

Use physical devices 1 and 2. They become logical GPUs 0 and 1. This is the validated configuration: `--split-mode tensor --tensor-split 16,9` weights the 32 GB MI100 heavier than the 7900 XTX (~22 GB usable), F16 KV cache is required by tensor mode, and the embedded MTP branch adds draft speculation (single slot). Row splitting is not supported by the MI100 path in this image (`device ROCm0 does not support split buffers`), and tensor mode is not supported for MoE models, which is why the jukebox runs MoE tracks in layer mode.

```bash
# Host: start an interactive container with only the MI100 and RX 7900 XTX visible.
HIP_VISIBLE_DEVICES=1,2 ./interactive-server.sh --detach

# Host: open a Bash console.
docker exec -it --user llama rocm-llama-interactive /bin/bash

# Container: start Qwen3.8-27B with the validated split and MTP.
llama-server \
  --hf-repo unsloth/Qwen3.8-27B-GGUF \
  --split-mode tensor \
  --tensor-split 16,9 \
  --ctx-size 262144 \
  --flash-attn on \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --spec-type draft-mtp \
  --spec-draft-n-max 3 \
  --parallel 1 \
  --host 127.0.0.1 \
  --port 8000 \
  -ngl all
```

For most interactive work prefer the jukebox (`./run-server-mi100.sh`), which applies exactly these settings through `models.ini`.

Q8 KV can reduce memory use if FP16 KV does not fit; use `--cache-type-k q8_0 --cache-type-v q8_0` and matching `--spec-draft-type-k q8_0 --spec-draft-type-v q8_0` as the fallback.

### Two R9700s: tensor-parallel mode, 256k context (only when vLLM is idle)

Use physical devices 0 and 3. Inside the container they become logical GPUs 0 and 1. The 256k configuration uses 16-bit FP16 KV cache. Do not run this while vLLM holds the pair:


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

### Container 2: MI100 and RX 7900 XTX, tensor split 16,9

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
  --split-mode tensor \
  --tensor-split 16,9 \
  --ctx-size 262144 \
  --flash-attn on \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --spec-type draft-mtp \
  --spec-draft-n-max 3 \
  --parallel 1 \
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

## Model jukebox (router mode)

`models.ini` is the jukebox preset: every section is a track the router can load, unload, and swap on demand. The three cached current models are enabled, and the container runs with `--models-max 3` so all tracks can stay resident at once. GGUF files are mmap'ed from the bind-mounted host cache (`~/.cache/huggingface`, ~1 TB free) and held in the host page cache (378 GB RAM), so switching between loaded tracks is near-instant and an unloaded track streams from NVMe. The three configured tracks are the curated listing; the router also exposes any extra quant variants present in the cache, so pruning a variant (for example the `Qwen3.6-27B` Q6 files or the former `Qwen3.5-2B` smoke-test entry) removes it from `/v1/models` after the next router start.

Launch it on the MI100 + RX 7900 XTX pair (ROCm cards 1 and 2):

```bash
./run-server-mi100.sh    # pins HIP_VISIBLE_DEVICES=1,2, publishes http://127.0.0.1:8000
./stop-server.sh
```

`run-server-mi100.sh` bind-mounts the working-tree `models.ini` over the image copy, so track edits take effect on the next launch without rebuilding the image. Cards 0 and 3 (the R9700 pair) are reserved for vLLM and must not be exposed to this launcher.

Tracks and settings (sampling values follow each model's Hugging Face card; context sizes are the models' native windows):

| Model ID (API) | Split | Context | Sampling (default mode) |
| --- | --- | --- | --- |
| `unsloth/Qwen3.8-27B-GGUF:Q8_0` (loaded at startup) | tensor 16,9 + MTP draft | 262144 | temp 1.0, top-p 0.95, top-k 20, min-p 0, presence 0 |
| `unsloth/Qwen3.6-27B-GGUF:Q8_0` | tensor 16,9 | 262144 | temp 1.0, top-p 0.95, top-k 20, min-p 0, presence 0 |
| `unsloth/Qwen3.6-35B-A3B-GGUF:Q8_0` (MoE) | layer 16,9 | 262144 | temp 1.0, top-p 0.95, top-k 20, min-p 0, presence 1.5 |
| `unsloth/gemma-4-31B-it-GGUF:Q8_0` | layer 16,9 | 262144 | temp 1.0, top-p 0.95, top-k 64 |

Qwen3.8-27B runs with the embedded MTP branch (`--spec-type draft-mtp`, depth 3, single slot), which was the validated fast path on cards 1, 2. The F16 KV cache in the `[*]` section is required by tensor split mode and validated at 256k context. The `16,9` split mirrors the MI100 (32 GB) to 7900 XTX (~22 GB usable) memory ratio with the validated 16:9 weighting.

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

## R9700 RDNA boosts experiment

The stable `rocm-llama-cpp:rocm714` image is the control image. The RDNA experiment uses a separate tag and applies the pinned `llama-cpp-rdna-boosts` delivery during the Docker build.

The current pins are:

- llama.cpp base: `ebbb18522`
- `llama-cpp-rdna-boosts` repository commit: `0cb5cf9b1e001d74a331d98cc1bbfbfe7d0c3412`
- delivery manifest: `v16-ebbb18522-r3`
- expected applied llama.cpp tree: `3f3dfcfaa1795e9bd475d56ea695b90daea5b5fa`
- R9700 target: `gfx1201`

The manifest's `v16-ebbb18522-r3` release name is not currently advertised as a remote Git tag, so use the pinned repository commit above rather than a moving branch or absent tag.

Build from this directory:

```bash
cd rocm_docker

export NEW_IMAGE=rocm-llama-cpp:rdna-boosts-20260918
export LLAMA_CPP_COMMIT=ebbb18522
export RDNA_BOOSTS_COMMIT=0cb5cf9b1e001d74a331d98cc1bbfbfe7d0c3412
export BUILD_JOBS=64

docker build --pull --no-cache \
  --build-arg LLAMA_CPP_COMMIT="$LLAMA_CPP_COMMIT" \
  --build-arg RDNA_BOOSTS_COMMIT="$RDNA_BOOSTS_COMMIT" \
  --build-arg BUILD_JOBS="$BUILD_JOBS" \
  -t "$NEW_IMAGE" \
  .
```

`Dockerfile` defaults `BUILD_JOBS` to `auto`, which uses `nproc`. Set it explicitly when the host has a preferred compile limit. The build compiles `gfx908`, `gfx1100`, and `gfx1201`; use `--build-arg BUILD_JOBS=64` for the current 64-core host.

For a build that must survive a terminal or desktop-session failure, run it detached and inspect the log later:

```bash
nohup docker build --pull --no-cache \
  --build-arg LLAMA_CPP_COMMIT="$LLAMA_CPP_COMMIT" \
  --build-arg RDNA_BOOSTS_COMMIT="$RDNA_BOOSTS_COMMIT" \
  --build-arg BUILD_JOBS="$BUILD_JOBS" \
  -t "$NEW_IMAGE" \
  . > agent_work/rdna-boosts-build-20260918.log 2>&1 < /dev/null &

echo "build pid=$!"
tail -f agent_work/rdna-boosts-build-20260918.log
```

Validate the image before starting a model server:

```bash
docker image inspect "$NEW_IMAGE" --format '{{.Id}} {{.Size}}'
docker run --rm --entrypoint /usr/local/bin/llama/llama-server \
  "$NEW_IMAGE" --version
```

Start an interactive container with only the two physical R9700 devices visible:

```bash
export CONTAINER_NAME=rocm-llama-rdna-boosts
export HOME_VOLUME=rocm-llama-home-rdna-boosts

HIP_VISIBLE_DEVICES=0,3 \
IMAGE="$NEW_IMAGE" \
CONTAINER_NAME="$CONTAINER_NAME" \
HOME_VOLUME="$HOME_VOLUME" \
./interactive-server.sh --detach

# Confirm llama.cpp sees two gfx1201 R9700 devices.
docker exec --user llama "$CONTAINER_NAME" llama-bench --list-devices
```

Run Qwen3.8-27B with the validated dual-R9700 tensor configuration:

```bash
docker exec --user llama "$CONTAINER_NAME" llama-server \
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

The model API is available at `http://127.0.0.1:8000` when using the default host network. Stop the experiment container when finished:

```bash
docker stop --time 30 "$CONTAINER_NAME"
```

The experiment build was intentionally kept separate from `rocm-llama-cpp:rocm714`; do not retag or overwrite the control image until the new image passes device, model-load, API, and performance checks.

## What is in the image

| Component | Current value |
| --- | --- |
| Base image | `rocm/pytorch:rocm7.14_ubuntu24.04_py3.12_pytorch_release_2.12.0` |
| llama.cpp | `9723942adc518b43c4b95dc4dce6906903eb5e09` |
| ROCm targets | `gfx908`, `gfx1100`, `gfx1201` |
| Binaries | `/usr/local/bin/llama/llama-server`, `/usr/local/bin/llama/llama-bench` |
| Runtime user | `llama`, in `video` and `render` groups |
| Default cache | `HF_HOME=/home/llama/.cache/huggingface`, Xet high-performance downloads |
| Interactive home | `rocm-llama-home:/home/llama` |
| Router port | `127.0.0.1:8000`, `--models-max 4` |

The image also contains `huggingface_hub` and `hf_transfer`. The source checkout is removed after compilation.

## Models

`models.ini` is copied into the image at `/etc/llama-server/models.ini`, and the launchers also bind-mount the working-tree copy over it. Its section names are the model IDs clients send in API requests. The four cached current models are enabled as jukebox tracks; see [the model jukebox section](#model-jukebox-router-mode) for the per-track settings and their Hugging Face sources.

For a small direct smoke test, the operations guide uses `unsloth/Qwen3.5-2B-GGUF`. Direct model loading uses `--hf-repo`; router entries use `hf =` in `models.ini`.

The router downloads missing tracks into the mounted cache on first use. Pre-download the largest track with the Hugging Face CLI:

```bash
hf download unsloth/Qwen3.6-35B-A3B-GGUF --include 'Qwen3.6-35B-A3B-Q8_0.gguf'
```

## Repository structure

```text
rocm_docker/
├── Dockerfile                 # ROCm base, llama.cpp build, runtime image
├── entrypoint.sh              # Cache setup and gosu privilege drop
├── interactive-server.sh      # Temporary interactive Bash container
├── run-server.sh              # Detached models.ini router (GPU set from environment)
├── run-server-mi100.sh        # Primary jukebox launcher, pinned to cards 1,2 (MI100+7900 XTX)
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

The `run-server*.sh` launchers bind-mount this repository's `models.ini` over the copy baked into the image, so jukebox edits need only a container restart, not a rebuild. The baked copy still applies when running the image directly (`docker run`).

`HIP_VISIBLE_DEVICES` uses ROCm enumeration order. It does not use PCI slot names, and the example `2,3` is not universal. See [GPU selection in the operations guide](docs/OPERATIONS.md#6-select-specific-gpus).

## API

The detached router uses host networking and the Dockerfile CMD binds `127.0.0.1:8000`, so the API is reachable from the host loopback only. Change the CMD to `0.0.0.0` if peer containers on a user-defined bridge must reach the router directly.

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
