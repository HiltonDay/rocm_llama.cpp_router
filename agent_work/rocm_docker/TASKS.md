# Tasks

## TASK-1: Verify Dockerfile builds cleanly

**Files:** `rocm_docker/Dockerfile`

Confirm base image tag resolves. Confirm llama.cpp compiles at pinned commit with `GGML_HIP=ON` for `gfx908;gfx1100`. Fix any broken apt deps or cmake flags.

Also remove the `COPY models.ini /etc/llama-server/models.ini` line — models.ini is out of scope for this simplified design.

**Done when:** `docker build -t rocm-llama-server .` exits 0. No models.ini COPY in Dockerfile.

---

## TASK-2: Replace entrypoint.sh

**Files:** `rocm_docker/entrypoint.sh`
**Depends on:** TASK-1

Replace file contents entirely with:

```sh
#!/bin/sh
mkdir -p /home/llama/.cache/huggingface
exec "$@"
```

Three lines. No set -e, no XDG exports, no stage conditionals, no setpriv calls.

**Done when:** File contains exactly those three lines.

---

## TASK-3: Add CMD to Dockerfile

**Files:** `rocm_docker/Dockerfile`
**Depends on:** TASK-1, TASK-2

Remove the commented-out stage blocks. Add active CMD:

```dockerfile
CMD ["/usr/local/bin/llama/llama-server", \
     "-fa", "1", "--parallel", "3", "--kv-unified", \
     "-ts", "9/16", "-ctk", "bf16", "-ctv", "bf16", \
     "--hf-repo", "unsloth/Qwen3.6-27B-GGUF:Q8_0", \
     "--temp", "0.6", "--top-p", "0.95", "--top-k", "20", \
     "--min-p", "0.0", "--presence-penalty", "0.0", "--repeat-penalty", "1.0", \
     "--reasoning-budget", "32768", "--ctx-size", "262144", \
     "--host", "0.0.0.0", "--port", "8000"]
```

**Done when:** `docker inspect rocm-llama-server | jq '.[].Config.Cmd'` shows the full flag list starting with `/usr/local/bin/llama/llama-server`.

---

## TASK-4: Replace run-server.sh

**Files:** `rocm_docker/run-server.sh`
**Depends on:** TASK-3

Replace file contents entirely with a single `docker run` command. No stage flags, no mode switches, no commented blocks.

```sh
#!/bin/bash
set -euo pipefail

[ -f .env ] && source .env

: "${MODELS_DIR:?MODELS_DIR must be set}"

docker run \
  --read-only --tmpfs /tmp --no-new-privileges \
  --network host \
  --device /dev/kfd --device /dev/dri \
  --group-add video --group-add render \
  -v "${MODELS_DIR}:/models:ro" \
  -v "${HOME}/.cache/huggingface:/home/llama/.cache/huggingface" \
  rocm-llama-server
```

**Done when:** Script runs without error and container starts successfully. No stage flags or commented blocks remain.

---

## TASK-5: Build and test

**Files:** none (verification only)
**Depends on:** TASK-1 through TASK-4

```sh
docker build -t rocm-llama-server .
bash run-server.sh &
sleep <model_load_time>
curl http://localhost:8000/health
```

**Done when:** `/health` returns HTTP 200. No GPU permission errors in container logs. HF cache persists after container restart.
