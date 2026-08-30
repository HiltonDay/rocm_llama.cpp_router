# ROCm container operations

This guide is the operational reference for the files in `rocm_docker/`. It covers the image lifecycle, interactive access, shutdown, versioned builds, benchmarking, and GPU selection. Each section ends with a test case.

Commands use `docker`, which may be Docker or a Podman Docker-compatible wrapper. Run them from the repository directory:

```bash
cd rocm_docker
```

The default image tag is:

```bash
export IMAGE=rocm-llama-cpp:rocm714
export TEST_REPO=unsloth/Qwen3.5-2B-GGUF
```

The scripts accept `IMAGE`, `HOME_VOLUME`, and `HIP_VISIBLE_DEVICES` from the environment. If `HIP_VISIBLE_DEVICES` is unset, the container can see all GPUs passed through `--device`.

## Quick start: interactive Qwen3.8-27B

Use this three-step sequence for a separate container launch and console:

```bash
# 1. Launch the interactive container in the background.
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

The default `./interactive-server.sh` command starts the container and opens Bash in one step. The interactive home volume is `rocm-llama-home:/home/llama`; Bash history is stored at `/home/llama/.bash_history` and survives container removal. Stop the foreground server with `Ctrl-C`, exit Bash, and stop the detached container:

```bash
docker stop --time 30 rocm-llama-interactive
```

## Quick start: Qwen3.8-27B multi-GPU modes

The validated ROCm device order is physical device 0=R9700, 1=MI100, 2=RX 7900 XTX, and 3=R9700. `HIP_VISIBLE_DEVICES` selects physical devices and exposes them to llama.cpp as logical devices starting at 0. The commands use the pinned llama.cpp options `--split-mode`, `--tensor-split`, and `--main-gpu`.

### Two R9700s: tensor-parallel mode with 256k context

Select physical devices 0 and 3. The selected cards become logical GPUs 0 and 1, and `--split-mode tensor` enables the parallelized tensor split:

```bash
# Host terminal, from rocm_docker/.
HIP_VISIBLE_DEVICES=0,3 ./interactive-server.sh --detach
docker exec -it --user llama rocm-llama-interactive /bin/bash

# Inside the container.
llama-server \\
  --hf-repo unsloth/Qwen3.8-27B-GGUF \\
  --split-mode tensor \\
  --tensor-split 1,1 \\
  --ctx-size 262144 \\
  --flash-attn on \\
  --host 127.0.0.1 \\
  --port 8000 \\
  -ngl all
```

### RX 7900 XTX and MI100: row-split mode with 200k context

Select physical devices 1 and 2. The MI100 is logical GPU 0 and is selected as the row-mode main GPU; the RX 7900 XTX is logical GPU 1:

```bash
# Host terminal, from rocm_docker/.
HIP_VISIBLE_DEVICES=1,2 ./interactive-server.sh --detach
docker exec -it --user llama rocm-llama-interactive /bin/bash

# Inside the container.
llama-server \\
  --hf-repo unsloth/Qwen3.8-27B-GGUF \\
  --split-mode row \\
  --tensor-split 1,1 \\
  --main-gpu 0 \\
  --ctx-size 204800 \\
  --flash-attn on \\
  --host 127.0.0.1 \\
  --port 8000 \\
  -ngl all
```

The two `--tensor-split 1,1` values request an equal model split across the two selected GPUs. These large contexts require sufficient model, KV-cache, and runtime workspace memory; reduce the context size if initialization reports an out-of-memory error. Stop either session with `Ctrl-C`, exit Bash, and run:

```bash
docker stop --time 30 rocm-llama-interactive
```

## Before starting

The host needs:

- A working ROCm installation with `/dev/kfd` and `/dev/dri`.
- Docker or a compatible Podman command.
- The `video` and `render` groups available to the container runtime.
- The requested GGUF files in the host Hugging Face cache, or network access for the first download.

The cache used by the interactive script is:

```text
host:      $HOME/.cache/huggingface
container: /home/llama/.cache/huggingface
HF_HOME:   /home/llama/.cache/huggingface
```

The detached router script uses the same host cache but mounts it at `/tmp/huggingface` and sets `HF_HOME=/tmp/huggingface` for the server process. The two paths are intentional; both refer to the same host cache.

## 1. Build a persistent image

A normal image build creates a tagged local image. The image remains after the build finishes and can be used by later `docker run` commands. The build compiles llama.cpp for `gfx908`, `gfx1100`, and `gfx1201`.

```bash
docker build -t "$IMAGE" .
```

The Dockerfile currently pins:

- ROCm base image: `rocm/pytorch:rocm7.14_ubuntu24.04_py3.12_pytorch_release_2.12.0`
- llama.cpp commit: `9723942adc518b43c4b95dc4dce6906903eb5e09`
- Build targets: `gfx908,gfx1100,gfx1201`
- Binaries: `llama-server` and `llama-bench`

Confirm that the image is persistent and contains the expected binaries:

```bash
docker image inspect "$IMAGE" --format '{{.Id}} {{.RepoTags}}'
docker run --rm --entrypoint /usr/local/bin/llama/llama-server "$IMAGE" --help >/dev/null
docker run --rm --entrypoint /usr/local/bin/llama/llama-bench "$IMAGE" --help >/dev/null
```

`--rm` applies only to these short-lived inspection containers. It does not remove the image.

### Test case 1: persistent image

Pass when `docker image inspect` prints the `rocm-llama-cpp:rocm714` tag and both help commands exit with status 0. If the image is missing, repeat the build from `rocm_docker/`.

## 2. Run the container and connect with Bash

Use the interactive launcher:

```bash
IMAGE="$IMAGE" ./interactive-server.sh
```

For a separate console connection, start it detached and use `docker exec`:

```bash
IMAGE="$IMAGE" ./interactive-server.sh --detach
docker exec -it --user llama rocm-llama-interactive /bin/bash
```

The launcher:

- Runs the image with the Dockerfile entrypoint.
- Drops from root to the `llama` user through `gosu`.
- Passes `/dev/kfd` and `/dev/dri` to the container.
- Mounts the Hugging Face cache read-write.
- Provides a writable, non-executable `/tmp` tmpfs for runtime state.
- Mounts the named `rocm-llama-home` volume at `/home/llama` so history persists.
- Removes the interactive container when Bash exits; the named volume remains.

Inside the container, verify the identity, paths, and binaries:

```bash
export TEST_REPO=unsloth/Qwen3.5-2B-GGUF
id
printf 'HF_HOME=%s\n' "$HF_HOME"
ls -l /dev/kfd /dev/dri
command -v llama-server llama-bench
llama-bench --list-devices
```

Run a direct server for a manual API check. Direct loading uses `--hf-repo`; `hf=...` is the syntax used inside `models.ini` router entries.

```bash
llama-server \
  --hf-repo "$TEST_REPO" \
  --host 127.0.0.1 \
  --port 8000 \
  --ctx-size 4096 \
  --flash-attn on \
  -ngl 99
```

From another host terminal, query the server:

```bash
curl --fail http://127.0.0.1:8000/v1/models
MODEL_ID=$(curl --silent --fail http://127.0.0.1:8000/v1/models | \
  python3 -c 'import json, sys; print(json.load(sys.stdin)["data"][0]["id"])')
curl --fail http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL_ID\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with one short sentence.\"}],\"max_tokens\":64}"
```

Stop a manually started server with `Ctrl-C`, then leave the shell with `exit` or `Ctrl-D`. Because the launcher uses `--rm`, the interactive container is removed after exit.

### Test case 2: interactive access

Pass when `id` shows `llama` with `video` and `render` groups, both device paths exist, `llama-bench --list-devices` runs, `/v1/models` returns JSON, and the chat request returns a non-empty completion. A model can take time to load on the first request.

## 3. Gracefully shut down the detached container

The detached launcher starts the router container as `rocm-llama`:

```bash
IMAGE="$IMAGE" ./run-server.sh
```

Check its status and logs:

```bash
docker ps --filter name=rocm-llama
docker logs rocm-llama
```

Stop it through the project script:

```bash
./stop-server.sh
```

`docker stop` sends the container's normal termination signal and waits for the runtime timeout. The container is configured with `--rm`, so it disappears after it stops. For a longer grace period during a large model swap or unload, use:

```bash
docker stop --time 30 rocm-llama
```

The interactive launcher is different: use `Ctrl-C` for a foreground server, then `exit` from Bash.

### Test case 3: graceful shutdown

Start the detached server, wait until `docker ps` reports it as running, then run `./stop-server.sh`. Pass when the command succeeds and this returns no container:

```bash
docker ps -a --filter name=rocm-llama --format '{{.Names}}'
```

If a container remains, inspect `docker logs rocm-llama` and `docker inspect rocm-llama` before removing it manually.

## 4. Build a new image version

Keep the working tag. Give a new build its own tag so it can be compared or rolled back.

### New llama.cpp commit

Set `LLAMA_CPP_COMMIT` to a commit or tag accepted by the upstream repository and choose a new image tag:

```bash
export NEW_COMMIT=<llama.cpp-commit-or-tag>
export NEW_IMAGE=rocm-llama-cpp:rocm714-<version>

docker build \
  --pull \
  --no-cache \
  --build-arg LLAMA_CPP_COMMIT="$NEW_COMMIT" \
  -t "$NEW_IMAGE" \
  .
```

`--no-cache` matters here. Without it, the cached clone and compile layers can leave the old llama.cpp revision in the image. `--pull` checks for a newer base image but does not change the Dockerfile's pinned base tag.

### Configuration-only version

Changes to `models.ini`, `entrypoint.sh`, or the launcher files require a new image only when the changed file is copied into the image. `models.ini` is copied into `/etc/llama-server/models.ini`, so rebuild after editing it:

```bash
docker build -t rocm-llama-cpp:models-<version> .
```

Use a non-default image with the scripts by setting `IMAGE`:

```bash
IMAGE="$NEW_IMAGE" ./interactive-server.sh
IMAGE="$NEW_IMAGE" ./run-server.sh
```

The detached router script uses the `models.ini` embedded in the image. Do not overwrite a working tag until the new tag passes the image and API checks.

### Test case 4: versioned rebuild

This concrete test keeps the current commit but gives the result a separate tag. Use a different commit in a real upgrade.

```bash
export VERSION=doc-test
export TEST_IMAGE="rocm-llama-cpp:rocm714-$VERSION"
docker build \
  --build-arg LLAMA_CPP_COMMIT=9723942adc518b43c4b95dc4dce6906903eb5e09 \
  -t "$TEST_IMAGE" \
  .
docker image inspect "$IMAGE" "$TEST_IMAGE" --format '{{.RepoTags}}'
docker run --rm --entrypoint /usr/local/bin/llama/llama-server \
  "$TEST_IMAGE" --help >/dev/null
```

Pass when both tags are present and the new tag executes the server help command. For an actual source upgrade, set `LLAMA_CPP_COMMIT` to the new commit and add `--pull --no-cache` as shown above. Remove the test tag after validation with `docker image rm "$TEST_IMAGE"` if it is no longer needed.

## 5. Run llama-bench in the container

`llama-bench` needs a local GGUF filename. The server's `--hf-repo` resolver is not a substitute for a benchmark model path, so locate the downloaded snapshot inside the interactive container.

Start the shell:

```bash
IMAGE="$IMAGE" ./interactive-server.sh
```

Inside the container:

```bash
MODEL=$(find "$HF_HOME/hub/models--unsloth--Qwen3.5-2B-GGUF/snapshots" \
  \( -type f -o -type l \) -name '*.gguf' -print -quit)
test -n "$MODEL" || { echo 'Qwen GGUF not found in HF cache' >&2; exit 1; }
printf 'Benchmark model: %s\n' "$MODEL"
```

List the devices before measuring:

```bash
llama-bench --list-devices
```

Run a small repeatable benchmark. The batch sizes and flash attention setting match the current tuning notes; adjust prompt and generation sizes for a shorter or longer run.

```bash
llama-bench \
  -m "$MODEL" \
  -t 1 \
  -ngl 99 \
  -fa on \
  -p 128,512,2048 \
  -n 128,512 \
  -b 16384 \
  -ub 2048 \
  -r 3
```

The output includes prompt-processing (`pp`) and text-generation (`tg`) measurements. Record the full output with the image tag, GPU selection, model filename, and host power/performance settings. Do not compare numbers from different GPU sets as if they were the same test.

### Test case 5: benchmark validation

Pass when `llama-bench --list-devices` lists the intended devices and the benchmark prints completed `pp` and `tg` rows without a model-loading, HIP architecture, or out-of-memory error. Save the output for later comparisons.

## 6. Select specific GPUs

The container receives the device nodes for all host GPUs. `HIP_VISIBLE_DEVICES` limits which ROCm devices llama.cpp can use after startup. It uses ROCm device indices, not necessarily PCI slot numbers.

First inspect the host and container enumeration:

```bash
rocminfo | grep -E 'Name:|Marketing Name:|gfx[0-9]+' | head -40
IMAGE="$IMAGE" ./interactive-server.sh
```

Inside the shell:

```bash
llama-bench --list-devices
```

Use the indices reported by the container. Do not assume that the two R9700 cards are `2,3`; that is only an example.

### Two R9700 cards only

If the device list identifies the R9700 cards as indices `2` and `3`, run:

```bash
HIP_VISIBLE_DEVICES=2,3 IMAGE="$IMAGE" ./interactive-server.sh
```

Inside the shell, verify that only those devices are visible:

```bash
llama-bench --list-devices
```

For the detached router, use the same selector:

```bash
HIP_VISIBLE_DEVICES=2,3 IMAGE="$IMAGE" ./run-server.sh
```

The `models.ini` default `tensor-split = 9,16` was tuned for the MI100 plus 7900 XTX setup. For two equal 32 GB R9700 cards, benchmark an equal split such as `tensor-split = 1,1` in a copied `models.ini`, rebuild the image, and compare the results. Do not assume the old split is correct for the R9700 pair.

### MI100 and 7900 XTX only

If those devices are indices `0` and `1`, run:

```bash
HIP_VISIBLE_DEVICES=0,1 IMAGE="$IMAGE" ./interactive-server.sh
```

For the current router configuration, this is the hardware set that matches the checked-in `tensor-split = 9,16` default most closely. Confirm the actual enumeration before using the values.

### One-off manual container

To test a selector without the launcher, pass it explicitly to `docker run`:

```bash
docker run --rm -it \
  --network host \
  --ipc=host \
  --device /dev/kfd \
  --device /dev/dri \
  --group-add video \
  --group-add render \
  --tmpfs /tmp:rw,noexec,nosuid,size=512m \
  --security-opt no-new-privileges \
  -e HIP_VISIBLE_DEVICES=2,3 \
  -v "$HOME/.cache/huggingface:/home/llama/.cache/huggingface" \
  "$IMAGE" \
  /bin/bash
```

### Test case 6: GPU selection

Run the benchmark device listing once with all GPUs and once with the selected `HIP_VISIBLE_DEVICES` value. Pass when the second listing contains only the intended GPU(s), and the benchmark completes using that set. If the list is unchanged, the indices are wrong or the container was started without forwarding `HIP_VISIBLE_DEVICES`.

## Router mode and model configuration

`run-server.sh` starts the Dockerfile CMD, which loads `/etc/llama-server/models.ini` with `--models-preset` and limits the router to one loaded model with `--models-max 1`. The model section header is the client-facing model ID. The router uses the model sections embedded in `models.ini`. The direct smoke tests in this guide use `$TEST_REPO` (`unsloth/Qwen3.5-2B-GGUF`) so they do not require loading a 27B model. Router checks use the model ID printed by `/v1/models`, unless the small test model has first been added to `models.ini` and the image rebuilt.

Check the router API after starting it:

```bash
curl --fail http://127.0.0.1:8000/v1/models
curl --fail http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"<model-id-from-v1-models>","messages":[{"role":"user","content":"Reply with exactly: API verified"}],"max_tokens":128,"temperature":0}'
```

The checked-in router CMD currently binds `0.0.0.0` because `run-server.sh` uses host networking. Restrict access with a firewall or change the CMD to `127.0.0.1` before using it on an untrusted network. The direct interactive example above binds to `127.0.0.1`.

## Troubleshooting

- **Model not found:** Check `$HF_HOME/hub/models--unsloth--Qwen3.5-2B-GGUF/snapshots` inside the container. The host cache must be mounted at the path used by the launcher.
- **`hipErrorNoBinaryForGpu`:** The image was not built for the selected architecture. Confirm `LLAMACPP_ROCM_ARCH` in the Dockerfile and rebuild with `--no-cache`.
- **`/dev/kfd: Permission denied`:** Check host group membership and the `--device`, `--group-add video`, and `--group-add render` flags.
- **`--flash-attn` argument error:** This image's 9723942adc518b43c4b95dc4dce6906903eb5e09 binary requires `--flash-attn on`, `off`, or `auto`.
- **Port 8000 occupied:** Run `ss -ltnp '( sport = :8000 )'`, stop the existing service, or choose another port in the manual command.
- **Out of memory:** Lower `--ctx-size`, use a smaller quantization, select more GPUs, or change the tensor split after benchmarking.
- **Slow or failed GPU selection:** Recheck indices with `llama-bench --list-devices`; `HIP_VISIBLE_DEVICES` uses ROCm enumeration order.
