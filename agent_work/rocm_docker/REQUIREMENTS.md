# Requirements

## REQ-1: Image Builds with ROCm llama.cpp

Docker image builds successfully. llama.cpp compiled from pinned commit `63d93d17336e41e4cc73a64452e5b1d2477abdb1` with `GGML_HIP=ON` targeting `gfx1100`. `llama-server` binary present at `/usr/local/bin/llama/llama-server`.

**Acceptance:** `docker build` exits 0. `docker run --rm <image> /usr/local/bin/llama/llama-server --version` prints version without error.

---

## REQ-2: Models Accessible in Container

Host models directory bind-mounted at `/models`. Host HF cache (`~/.cache/huggingface`) bind-mounted at `/home/llama/.cache/huggingface` to persist downloads across container restarts.

**Acceptance:** File written to host models dir is readable at `/models` inside a running container. HF download on first run persists across container restarts.

---

## REQ-3: Auto-Start Server on Boot

Container starts `/usr/local/bin/llama/llama-server` automatically on `docker run` with no extra arguments. Server binds to `0.0.0.0:8000`.

**Acceptance:** `docker run <image>` starts server. `curl http://localhost:8000/health` returns HTTP 200 within model load time.

---

## REQ-4: GPU Access

Container has access to AMD GPU via `/dev/kfd` and `/dev/dri`. Process runs as `llama` user with `video` and `render` group membership.

**Acceptance:** `docker run --device /dev/kfd --device /dev/dri --group-add video --group-add render <image> /usr/local/bin/llama/llama-server --version` exits 0 with no GPU permission errors in stderr.
