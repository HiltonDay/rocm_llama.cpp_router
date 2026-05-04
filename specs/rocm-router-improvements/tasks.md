# Implementation Plan: ROCm Router Improvements

## Overview

Restructure three existing files (Dockerfile, entrypoint.sh, run-server.sh) and create one new file (TEST_PLAYBOOK.md) so that all four stages of the llama.cpp inference server are present from the start. Progression between stages happens by commenting/uncommenting clearly marked sections. Each task modifies exactly one file and is self-contained with enough detail for an AI agent to implement without reading the full design document.

## Tasks

- [ ] 1. Restructure the Dockerfile CMD section for staged progression
  - **File:** `research/rocm_llama.cpp_router/Dockerfile`
  - **Current state:** The file has a single `CMD` at the end: `CMD ["--models-preset", "/etc/llama-server/models.ini", "--host", "127.0.0.1", "--port", "8000"]`
  - **What to change:** Replace everything from the `EXPOSE 8000` line onwards (keeping `EXPOSE 8000`) with the new staged ENTRYPOINT/CMD section. The build section, user/group setup, COPY commands, and EXPOSE remain unchanged.
  - **Target state — replace the final section (from ENTRYPOINT onwards) with:**
    ```dockerfile
    ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

    # ============================================================
    # STAGE 1 & 2: No CMD — arguments come from docker run
    # ============================================================
    # Stages 1 and 2 pass arguments via docker run command line.
    # No CMD needed — entrypoint.sh handles whatever is passed.

    # ============================================================
    # STAGE 3: Auto-start single model (uncomment for Stage 3)
    # ============================================================
    # CMD ["--model", "hf=unsloth/Qwen3.6-27B-GGUF:Q8_0", \
    #      "--host", "127.0.0.1", "--port", "8000", \
    #      "--ctx-size", "262144", "--flash-attn", \
    #      "--parallel", "3", "--temp", "0.6", "--top-p", "0.95", "--top-k", "20"]

    # ============================================================
    # STAGE 4: Router mode with models-preset (uncomment for Stage 4)
    # ============================================================
    # CMD ["--models-preset", "/etc/llama-server/models.ini", \
    #      "--models-max", "1", \
    #      "--host", "127.0.0.1", "--port", "8000"]
    ```
  - **Key points:** ENTRYPOINT is constant (always entrypoint.sh). No CMD is active for Stages 1-2. Only one CMD block should be uncommented at a time. The last uncommented CMD wins in Docker.
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 6.1_

- [ ] 2. Add --keep-alive mode to entrypoint.sh for Stage 2
  - **File:** `research/rocm_llama.cpp_router/entrypoint.sh`
  - **Current state:** The file has XDG setup, a `--shell` detection block, and a default `exec setpriv ... llama-server "$@"` block.
  - **What to change:** Insert a commented-out `--keep-alive` block between the `--shell` block and the default exec block. Also add section header comments to the existing blocks for consistency.
  - **Target state — the complete file should become:**
    ```bash
    #!/bin/sh
    set -e

    # ============================================================
    # XDG BASE DIRECTORY SETUP
    # All under /tmp for read-only filesystem compatibility
    # ============================================================
    mkdir -p /tmp/llama-cache /tmp/llama-config /tmp/llama-data
    chmod 1777 /tmp/llama-cache /tmp/llama-config /tmp/llama-data

    export XDG_CACHE_HOME=/tmp/llama-cache
    export XDG_CONFIG_HOME=/tmp/llama-config
    export XDG_DATA_HOME=/tmp/llama-data

    # ============================================================
    # STAGE 1: Interactive debug shell
    # If first argument is --shell, sh, or bash, drop to shell as llama user
    # Usage: docker run ... <image> --shell
    # ============================================================
    if [ "${1:-}" = "--shell" ] || [ "${1:-}" = "sh" ] || [ "${1:-}" = "bash" ]; then
        exec setpriv --reuid=$(id -u llama) --regid=$(id -g llama) --init-groups --inh-caps=-all \
            "$@"
    fi

    # ============================================================
    # STAGE 2: Keep-alive mode (uncomment for Stage 2)
    # Server runs in background; container stays alive for exec debugging
    # If server crashes, container remains running for diagnosis
    # Usage: docker run ... <image> --keep-alive <server-args...>
    # ============================================================
    # if [ "${1:-}" = "--keep-alive" ]; then
    #     shift  # remove --keep-alive from args
    #     setpriv --reuid=$(id -u llama) --regid=$(id -g llama) --init-groups --inh-caps=-all \
    #         /usr/local/bin/llama/llama-server "$@" &
    #     SERVER_PID=$!
    #     echo "llama-server started as PID $SERVER_PID"
    #     # Wait for server; if it exits, sleep forever so container stays up for debugging
    #     wait $SERVER_PID || true
    #     echo "llama-server exited (PID $SERVER_PID). Container staying alive for debugging."
    #     echo "Exec in with: docker exec -it <container> /usr/local/bin/entrypoint.sh --shell"
    #     tail -f /dev/null
    # fi

    # ============================================================
    # STAGE 3 & 4: Default — drop to llama user and run llama-server
    # Arguments come from CMD (Stage 3/4) or docker run (Stage 2 without keep-alive)
    # --init-groups rebuilds supplementary groups from /etc/group (video, render)
    # --inh-caps=-all drops all inheritable capabilities
    # ============================================================
    exec setpriv --reuid=$(id -u llama) --regid=$(id -g llama) --init-groups --inh-caps=-all \
        /usr/local/bin/llama/llama-server "$@"
    ```
  - **Key points:** The `--keep-alive` block is entirely commented out. When uncommented for Stage 2, it runs llama-server in the background and keeps the container alive if the server crashes (satisfying Requirement 3.7). The `--shell` block and default exec block are unchanged in logic, only gaining section header comments.
  - _Requirements: 2.1, 3.1, 3.7, 6.3, 9.7, 9.8_

- [ ] 3. Restructure run-server.sh into 4 stage blocks
  - **File:** `research/rocm_llama.cpp_router/run-server.sh`
  - **Current state:** The file has a single `docker run -d` command that passes no extra args (relying on Dockerfile CMD for router mode).
  - **What to change:** Replace the entire file content with the 4-stage version. Stage 1 is active (uncommented), Stages 2-4 are commented out. Each block is self-contained with all flags and inline documentation.
  - **Target state — the complete file should become:**
    ```bash
    #!/usr/bin/env bash
    # run-server.sh — Launch llama.cpp server container
    #
    # STAGE PROGRESSION:
    #   1. Uncomment the desired stage's docker run block
    #   2. Comment out all other stage blocks
    #   3. Run this script
    #
    # Security hardening (all stages):
    #   --read-only           : immutable container filesystem
    #   --tmpfs /tmp          : writable temp with noexec,nosuid,64MB limit
    #   --no-new-privileges   : prevent privilege escalation via setuid/setgid
    #   --network host        : use host network (server binds to 127.0.0.1)
    #   --device /dev/kfd     : AMD GPU kernel fusion driver
    #   --device /dev/dri     : AMD GPU direct rendering interface
    #   --group-add video     : GPU access group
    #   --group-add render    : GPU render group
    #   ,z SELinux label      : shared mount label for SELinux hosts
    #
    set -euo pipefail

    IMAGE_NAME="llama-cpp-server"
    CONTAINER_NAME="llama-server"
    HF_CACHE="${HF_CACHE_DIR:-$HOME/.cache/huggingface}"
    MODELS_DIR="${MODELS_DIR:-$HOME/models}"

    mkdir -p "$HF_CACHE" "$MODELS_DIR"

    # Clean up existing container if present
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
      docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    fi

    # ============================================================
    # STAGE 1: Interactive Debug Image
    # Starts an interactive shell as llama user.
    # Manually start llama-server from inside the container.
    # ============================================================
    docker run -it \
      --name "$CONTAINER_NAME" \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=64m \
      --security-opt no-new-privileges:true \
      --device /dev/kfd \
      --device /dev/dri \
      --group-add video \
      --group-add render \
      --network host \
      --mount type=bind,source="$HF_CACHE",target=/huggingface,z \
      --mount type=bind,source="$MODELS_DIR",target=/models,readonly,z \
      "$IMAGE_NAME" \
      --shell

    # ============================================================
    # STAGE 2: Script-Initiated Server with Debug Access
    # Server starts via --keep-alive; container stays up if server crashes.
    # Debug with: docker exec -it llama-server /usr/local/bin/entrypoint.sh --shell
    # ============================================================
    # docker run -d \
    #   --name "$CONTAINER_NAME" \
    #   --read-only \
    #   --tmpfs /tmp:rw,noexec,nosuid,size=64m \
    #   --security-opt no-new-privileges:true \
    #   --device /dev/kfd \
    #   --device /dev/dri \
    #   --group-add video \
    #   --group-add render \
    #   --network host \
    #   --mount type=bind,source="$HF_CACHE",target=/huggingface,z \
    #   --mount type=bind,source="$MODELS_DIR",target=/models,readonly,z \
    #   "$IMAGE_NAME" \
    #   --keep-alive \
    #   --model hf=unsloth/Qwen3.6-27B-GGUF:Q8_0 \
    #   --host 127.0.0.1 --port 8000 \
    #   --ctx-size 262144 --flash-attn \
    #   --parallel 3 --temp 0.6 --top-p 0.95 --top-k 20

    # ============================================================
    # STAGE 3: Auto-Start Server Image
    # Server starts automatically via Dockerfile CMD.
    # No extra arguments needed — CMD provides them.
    # Debug with: docker exec -it llama-server /usr/local/bin/entrypoint.sh --shell
    # ============================================================
    # docker run -d \
    #   --name "$CONTAINER_NAME" \
    #   --read-only \
    #   --tmpfs /tmp:rw,noexec,nosuid,size=64m \
    #   --security-opt no-new-privileges:true \
    #   --device /dev/kfd \
    #   --device /dev/dri \
    #   --group-add video \
    #   --group-add render \
    #   --network host \
    #   --mount type=bind,source="$HF_CACHE",target=/huggingface,z \
    #   --mount type=bind,source="$MODELS_DIR",target=/models,readonly,z \
    #   "$IMAGE_NAME"

    # ============================================================
    # STAGE 4: Production Router Mode
    # Server starts in router mode via Dockerfile CMD.
    # Uses --models-preset for multi-model swap.
    # No extra arguments needed — CMD provides them.
    # Debug with: docker exec -it llama-server /usr/local/bin/entrypoint.sh --shell
    # ============================================================
    # docker run -d \
    #   --name "$CONTAINER_NAME" \
    #   --read-only \
    #   --tmpfs /tmp:rw,noexec,nosuid,size=64m \
    #   --security-opt no-new-privileges:true \
    #   --device /dev/kfd \
    #   --device /dev/dri \
    #   --group-add video \
    #   --group-add render \
    #   --network host \
    #   --mount type=bind,source="$HF_CACHE",target=/huggingface,z \
    #   --mount type=bind,source="$MODELS_DIR",target=/models,readonly,z \
    #   "$IMAGE_NAME"
    ```
  - **Key points:** Stage 1 uses `docker run -it` (interactive) with `--shell`. Stages 2-4 use `docker run -d` (detached). Stage 2 passes `--keep-alive` plus explicit server args. Stages 3 and 4 pass no extra args (Dockerfile CMD provides them). The docker run blocks for Stages 3 and 4 are identical — the difference is which CMD is uncommented in the Dockerfile.
  - _Requirements: 2.1, 3.1, 4.2, 5.1, 6.2, 6.5, 8.1, 8.2, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 10.1, 10.2, 10.5, 10.6_

- [ ] 4. Checkpoint — Verify staged files are internally consistent
  - Ensure the three modified files (Dockerfile, entrypoint.sh, run-server.sh) are consistent with each other:
    - Dockerfile ENTRYPOINT points to `/usr/local/bin/entrypoint.sh`
    - Stage 2 in run-server.sh passes `--keep-alive` which entrypoint.sh handles
    - Stage 3 CMD in Dockerfile matches the single-model args pattern
    - Stage 4 CMD in Dockerfile uses `--models-preset` and `--models-max 1`
    - All stages use the same security flags (read-only, tmpfs, no-new-privileges, network host, device flags, group-add, SELinux labels)
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Create TEST_PLAYBOOK.md with complete manual verification for all stages
  - **File:** `research/rocm_llama.cpp_router/TEST_PLAYBOOK.md` (new file)
  - **What to create:** A single comprehensive document covering pre-flight checks, all four stages with exact console commands and expected outputs, troubleshooting, and stage progression instructions.
  - **Document structure (each section described below with exact content guidance):**
  - [ ] 5.1 Write the Pre-Flight Checklist section
    - **Section title:** `## Pre-Flight Checklist`
    - **Content must include these exact verification steps:**
      - Check ROCm driver: `rocminfo | head -20` — expect "HSA Runtime" and agent entries
      - Check Docker: `docker --version` — expect version 20+
      - Check GPU devices: `ls -la /dev/kfd /dev/dri/render*` — expect device nodes exist with correct permissions
      - Check HF cache exists: `ls ~/.cache/huggingface/hub/ | head -5` — expect model directories
      - Check models downloaded (one command per model):
        - `ls ~/.cache/huggingface/hub/models--unsloth--Qwen3.6-27B-GGUF/blobs/ | wc -l`
        - `ls ~/.cache/huggingface/hub/models--unsloth--gemma-4-31B-it-GGUF/blobs/ | wc -l`
        - `ls ~/.cache/huggingface/hub/models--unsloth--Qwen3.6-35B-A3B-GGUF/blobs/ | wc -l`
        - `ls ~/.cache/huggingface/hub/models--unsloth--gemma-4-26B-A4B-it-GGUF/blobs/ | wc -l`
      - Check image built: `docker images llama-cpp-server` — expect image listed with recent timestamp
      - Build the image if needed: `docker build -t llama-cpp-server .`
    - _Requirements: 7.3_
  - [ ] 5.2 Write the Stage 1 verification section
    - **Section title:** `## Stage 1: Interactive Debug Image`
    - **Preamble:** State that Stage 1 is the default — run-server.sh launches with `--shell` and no code changes needed.
    - **Launch command:** `./run-server.sh` (this runs the Stage 1 block which does `docker run -it ... --shell`)
    - **Verification steps (each with Command, Expected output, If it fails):**
      1. Verify you're the llama user: `id` — expect `uid=...(llama) gid=...(llama) groups=...(llama),video,render`
      2. Verify GPU device access: `ls -la /dev/kfd /dev/dri/render*` — expect readable device nodes
      3. Verify environment variables: `env | grep -E '(XDG|LD_LIBRARY|HF_HOME)'` — expect XDG_CACHE_HOME=/tmp/llama-cache, XDG_CONFIG_HOME=/tmp/llama-config, XDG_DATA_HOME=/tmp/llama-data, LD_LIBRARY_PATH containing /usr/local/bin/llama, HF_HOME=/huggingface
      4. Verify HF cache mount: `ls /huggingface/hub/ | head -5` — expect model directories
      5. Verify models mount: `ls /models/` — expect directory listing (may be empty if no models placed there)
      6. Verify library path: `ls /usr/local/bin/llama/llama-server` — expect file exists
      7. Verify shared libraries: `ldd /usr/local/bin/llama/llama-server | grep "not found"` — expect no output (all libs found)
      8. Verify writable tmp: `touch /tmp/test && rm /tmp/test` — expect no error
      9. Verify read-only filesystem: `touch /test 2>&1` — expect "Read-only file system"
      10. Manual server start: `/usr/local/bin/llama/llama-server --model hf=unsloth/Qwen3.6-27B-GGUF:Q8_0 --host 127.0.0.1 --port 8000 --ctx-size 4096 --flash-attn` — expect server startup logs showing GPU detection and model loading
      11. HTTP test (from another terminal on host): `curl http://127.0.0.1:8000/v1/models` — expect JSON with model name
      12. Stop server: Ctrl+C in the container shell
      13. Exit container: `exit`
    - **Stage Gate 1 checklist:** All 9 environment checks pass + manual server starts + HTTP responds
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 7.2, 8.3, 8.4_
  - [ ] 5.3 Write the Stage 2 verification section
    - **Section title:** `## Stage 2: Script-Initiated Server with Debug Access`
    - **Progression instructions:** Exact lines to comment/uncomment:
      - In `run-server.sh`: Comment out the Stage 1 block (add `#` to lines 38-50). Uncomment the Stage 2 block (remove `#` from lines 57-71).
      - In `entrypoint.sh`: Uncomment the `--keep-alive` block (remove `#` from lines 27-37).
      - No Dockerfile changes needed.
      - No image rebuild needed.
    - **Launch command:** `./run-server.sh` (now runs Stage 2 detached with --keep-alive)
    - **Verification steps:**
      1. Verify container running: `docker ps --filter name=llama-server` — expect container listed with status "Up"
      2. Verify server logs: `docker logs llama-server` — expect "llama-server started as PID" message followed by model loading logs
      3. Wait for model load (watch logs): `docker logs -f llama-server` — expect "model loaded" or similar, then Ctrl+C
      4. HTTP test: `curl http://127.0.0.1:8000/v1/models` — expect JSON response with model name
      5. Chat completion test: `curl http://127.0.0.1:8000/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"unsloth/Qwen3.6-27B-GGUF:Q8_0","messages":[{"role":"user","content":"Say hello in one word"}]}'` — expect JSON response with completion
      6. Exec into running container: `docker exec -it llama-server /usr/local/bin/entrypoint.sh --shell` — expect shell prompt
      7. Inside exec shell — verify environment: `env | grep -E '(XDG|LD_LIBRARY|HF_HOME)'` — expect same vars as Stage 1
      8. Inside exec shell — verify server process: `ps aux | grep llama-server` — expect llama-server process running as llama user
      9. Inside exec shell — check GPU memory: `cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null || echo "check rocm-smi on host"` — expect non-zero VRAM usage
      10. Exit exec shell: `exit`
      11. Stop container: `docker stop llama-server && docker rm llama-server`
    - **Keep-alive test (optional):** Kill the server process inside the container to verify it stays alive:
      - `docker exec llama-server kill $(docker exec llama-server pgrep llama-server)`
      - `docker logs llama-server | tail -5` — expect "llama-server exited... Container staying alive for debugging"
      - `docker ps --filter name=llama-server` — expect container still running
    - **Stage Gate 2 checklist:** Container starts detached + server loads model + HTTP responds + exec debugging works + logs accessible
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 7.2_
  - [ ] 5.4 Write the Stage 3 verification section
    - **Section title:** `## Stage 3: Auto-Start Server Image`
    - **Progression instructions:**
      - In `Dockerfile`: Uncomment the Stage 3 CMD block (remove `# ` from the CMD lines). Keep Stage 4 CMD commented.
      - In `run-server.sh`: Comment out Stage 2 block. Uncomment Stage 3 block.
      - In `entrypoint.sh`: No changes needed (keep-alive block can stay uncommented or be re-commented — it won't trigger because Stage 3 doesn't pass `--keep-alive`).
      - **Rebuild image:** `docker build -t llama-cpp-server .`
    - **Launch command:** `./run-server.sh` (now runs Stage 3 — no extra args, CMD provides them)
    - **Verification steps:**
      1. Verify container running: `docker ps --filter name=llama-server` — expect container listed
      2. Verify auto-start in logs: `docker logs llama-server` — expect llama-server startup without any "keep-alive" messages (direct exec, not backgrounded)
      3. Wait for model load: `docker logs -f llama-server` — expect model loaded message
      4. HTTP test: `curl http://127.0.0.1:8000/v1/models` — expect JSON with model
      5. Stop/start cycle: `docker stop llama-server && docker start llama-server` — expect container restarts
      6. Wait for reload: `sleep 30 && curl http://127.0.0.1:8000/v1/models` — expect JSON response (server auto-restarted)
      7. Verify logs after restart: `docker logs --since 1m llama-server` — expect fresh startup sequence
      8. Exec debug access: `docker exec -it llama-server /usr/local/bin/entrypoint.sh --shell` — expect shell
      9. Inside exec — verify server: `ps aux | grep llama-server` — expect process running
      10. Exit and cleanup: `exit` then `docker stop llama-server && docker rm llama-server`
    - **Stage Gate 3 checklist:** Auto-starts on container launch + stop/start cycle works + HTTP responds after restart + exec debugging works
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 7.2_
  - [ ] 5.5 Write the Stage 4 verification section
    - **Section title:** `## Stage 4: Production Router Mode`
    - **Progression instructions:**
      - In `Dockerfile`: Comment out Stage 3 CMD. Uncomment Stage 4 CMD block.
      - In `run-server.sh`: Comment out Stage 3 block. Uncomment Stage 4 block. (Note: Stage 3 and 4 docker run blocks are identical — the difference is the Dockerfile CMD.)
      - **Rebuild image:** `docker build -t llama-cpp-server .`
    - **Launch command:** `./run-server.sh`
    - **Verification steps:**
      1. Verify container running: `docker ps --filter name=llama-server` — expect container listed
      2. Verify router mode in logs: `docker logs llama-server` — expect "models-preset" or INI loading messages
      3. List all models: `curl http://127.0.0.1:8000/v1/models` — expect JSON listing all 4 models from models.ini
      4. Chat with startup model (Qwen3.6-27B, has load-on-startup=true): `curl http://127.0.0.1:8000/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"unsloth/Qwen3.6-27B-GGUF:Q8_0","messages":[{"role":"user","content":"Say hello in one word"}]}'` — expect completion response
      5. Model swap test — request a different model: `time curl http://127.0.0.1:8000/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"unsloth/gemma-4-31B-it-GGUF:Q8_0","messages":[{"role":"user","content":"Say hello in one word"}]}'` — expect completion response; `time` shows swap duration (expect 3-10 seconds for first request to new model)
      6. Verify swap in logs: `docker logs --since 2m llama-server | grep -i "unload\|load\|swap"` — expect unload/load messages
      7. Error handling — unknown model: `curl http://127.0.0.1:8000/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"nonexistent/model","messages":[{"role":"user","content":"test"}]}'` — expect error response (HTTP 400 or 404)
      8. Second swap — back to original: `time curl http://127.0.0.1:8000/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"unsloth/Qwen3.6-27B-GGUF:Q8_0","messages":[{"role":"user","content":"Confirm swap back"}]}'` — expect completion; timing shows swap
      9. Exec debug access: `docker exec -it llama-server /usr/local/bin/entrypoint.sh --shell` — expect shell
      10. Cleanup: `exit` then `docker stop llama-server && docker rm llama-server`
    - **Stage Gate 4 checklist:** Router mode starts + all models listed + chat works + model swap works within expected timing + unknown model returns error + exec debugging works
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 7.2_
  - [ ] 5.6 Write the Troubleshooting section
    - **Section title:** `## Troubleshooting`
    - **Must cover these failure scenarios with diagnostic commands and resolutions:**
      1. **GPU device permission errors** — `ls -la /dev/kfd /dev/dri/render*` on host; check user is in video/render groups on host; verify `--device` and `--group-add` flags in docker run
      2. **Library path issues** — `docker exec llama-server ldd /usr/local/bin/llama/llama-server`; check LD_LIBRARY_PATH; verify libraries copied during build
      3. **Mount permission errors** — `docker exec llama-server ls -la /huggingface /models`; check SELinux labels (`,z`); check host directory permissions
      4. **Port binding failures** — `lsof -i :8000` on host; `ss -tlnp | grep 8000`; another process using port 8000
      5. **Server crash diagnosis** — `docker logs llama-server`; check for OOM (model too large for VRAM); check GPU architecture mismatch; verify `--ctx-size` isn't too large
      6. **Model loading failures** — verify model exists in HF cache: `ls ~/.cache/huggingface/hub/models--<org>--<model>/`; check model format is GGUF; verify HF_HOME env var inside container
      7. **Container exits immediately** — `docker inspect llama-server --format '{{.State.ExitCode}}'`; `docker logs llama-server`; common causes: missing GPU, wrong arch, permission denied on devices
      8. **Read-only filesystem errors** — verify tmpfs mount at /tmp; check XDG vars point to /tmp subdirs; verify entrypoint.sh creates dirs before server starts
    - _Requirements: 7.4, 7.5, 8.5_
  - [ ] 5.7 Write the Stage Progression Reference section
    - **Section title:** `## Stage Progression Reference`
    - **Content:** A quick-reference table showing exactly which lines to comment/uncomment in which files to move between stages. Format:
      - Table with columns: From → To | Dockerfile | entrypoint.sh | run-server.sh | Rebuild needed?
      - Rows: Stage 1→2, Stage 2→3, Stage 3→4
      - Each cell states the exact action (e.g. "Uncomment lines 27-37" or "No change")
    - Also include a reminder: "Only one stage's docker run block should be active in run-server.sh. Only one CMD block should be uncommented in Dockerfile (for Stages 3-4)."
    - _Requirements: 6.4, 7.6_

- [ ] 6. Checkpoint — Review TEST_PLAYBOOK.md completeness
  - Verify TEST_PLAYBOOK.md covers all requirements from Requirement 7 (Test Playbook Documentation)
  - Verify every stage has: launch command, numbered verification steps with exact commands, expected outputs, failure guidance, and a stage gate checklist
  - Verify the troubleshooting section covers all scenarios from the design's Error Handling section
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Update README.md with stage documentation
  - **File:** `research/rocm_llama.cpp_router/README.md`
  - **What to change:** Update the README to reflect the staged approach. The current README documents only the final router mode. Changes needed:
    1. Add a "Stages" section after the "Prerequisites" section explaining the 4-stage progression concept (2-3 sentences per stage)
    2. Update the "Run" section to reference `./run-server.sh` and note that it defaults to Stage 1 (interactive debug)
    3. Add a note pointing to `TEST_PLAYBOOK.md` for detailed verification instructions
    4. Keep all other sections (Models table, Prerequisites, Pre-download, Build, Usage, Manage, Customize, Security) unchanged
  - **New "Stages" section content (insert after Prerequisites):**
    ```markdown
    ## Stages

    The server progresses through four stages. All stages are present in the code from the start — progression happens by commenting/uncommenting marked sections. See `TEST_PLAYBOOK.md` for detailed verification at each stage.

    | Stage | Mode | How to run |
    |-------|------|-----------|
    | 1 | Interactive Debug | `./run-server.sh` (default) — drops to shell inside container |
    | 2 | Script-Initiated Server | Detached container, server started with --keep-alive |
    | 3 | Auto-Start Server | Detached container, server starts via Dockerfile CMD |
    | 4 | Production Router | Detached container, router mode with models-preset |
    ```
  - **Update to "Run" section:** Replace the current content with:
    ```markdown
    ## Run

    ```bash
    # Default: Stage 1 interactive debug shell
    ./run-server.sh
    ```

    The script defaults to Stage 1 (interactive debug). See `TEST_PLAYBOOK.md` for stage progression instructions and verification steps.
    ```
  - _Requirements: 7.1, 6.2_

- [ ] 8. Final checkpoint — Verify all files are consistent and complete
  - Review all modified/created files for internal consistency
  - Verify run-server.sh is executable (`chmod +x`)
  - Verify entrypoint.sh is executable (`chmod +x`)
  - Verify the Dockerfile ENTRYPOINT path matches the COPY destination
  - Verify models.ini path in Dockerfile COPY matches the Stage 4 CMD `--models-preset` path
  - Verify all 10 requirements are covered by the implementation
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- No tasks are marked optional — this is infrastructure work with no property-based tests (the design explicitly states PBT does not apply)
- Each task modifies exactly one file for clear, sequential execution
- The test playbook (Task 5) is the primary verification mechanism — it IS the test suite, executed manually against real hardware
- All later-stage code is present but commented out from the start — progression is by uncommenting, not writing new code
- Tasks are ordered so each builds on the previous: Dockerfile first (sets the ENTRYPOINT/CMD contract), then entrypoint.sh (implements the dispatch logic), then run-server.sh (provides the docker run invocations), then TEST_PLAYBOOK.md (documents how to verify everything), then README (summarises for readers)
