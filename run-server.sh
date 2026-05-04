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
