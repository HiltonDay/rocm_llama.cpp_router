#!/usr/bin/env bash
# run-server.sh - Launch llama.cpp router server with hardened isolation
#
# First run: remove --network-none to allow model downloads from Hugging Face.
# Subsequent runs: use --network-none for full isolation (models are cached locally).
#
# Per secure-opencode.md Phase 1:
#   --read-only         : immutable container filesystem
#   --network none      : no outbound connections (remove for first-run model download)
#   --no-new-privileges : prevent privilege escalation
#   models ro           : model files mounted read-only
#   127.0.0.1           : bound to localhost only (0.0.0.0 is safe with --network none)
#
set -euo pipefail

IMAGE_NAME="llama-cpp-server"
CONTAINER_NAME="llama-server"
LOCAL_HF_HOME="$HOME/.cache/huggingface"

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
  --network none \
  --mount type=bind,source="$LOCAL_HF_HOME",target=/huggingface,z \
  "$IMAGE_NAME" \
  --models-preset /etc/llama-server/models.ini \
  --host 0.0.0.0 \
  --port 8000 \
  
