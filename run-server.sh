#!/bin/bash
set -euo pipefail

IMAGE="${IMAGE:-rocm-llama-cpp:rocm724}"
GPU_ENV=()
if [[ -n "${HIP_VISIBLE_DEVICES:-}" ]]; then
  GPU_ENV+=(--env "HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES}")
fi

# The image CMD starts llama-server in router mode using models.ini.
docker run -d \
  --rm \
  --name rocm-llama \
  --network host \
  --ipc=host \
  --device /dev/kfd \
  --device /dev/dri \
  --group-add video \
  --group-add render \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=512m \
  --security-opt no-new-privileges \
  -v "${HOME}/.cache/huggingface:/tmp/huggingface" \
  -e HF_HOME=/tmp/huggingface \
  "${GPU_ENV[@]}" \
  "${IMAGE}"
