#!/usr/bin/env bash
# run-server.sh - Launch llama.cpp router server with hardened isolation
#
# Uses --network host for localhost-only access (server binds to 127.0.0.1).
# Models are pre-downloaded on host; --offline prevents any HF network calls.
#
# Per secure-opencode.md Phase 1:
#   --read-only         : immutable container filesystem
#   --no-new-privileges : prevent privilege escalation
#   HF cache readonly   : model files mounted read-only
#   127.0.0.1           : bound to localhost only
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

docker run -d \
  --name "$CONTAINER_NAME" \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --security-opt no-new-privileges:true \
  --device /dev/kfd \
  --device /dev/dri \
  --group-add video \
  --group-add render \
  --network host \
  --mount type=bind,source="$HF_CACHE",target=/huggingface,readonly,z \
  --mount type=bind,source="$MODELS_DIR",target=/models,readonly,z \
  "$IMAGE_NAME" \
  --models-preset /etc/llama-server/models.ini \
  --host 127.0.0.1 \
  --port 8000 \
  --offline
  
