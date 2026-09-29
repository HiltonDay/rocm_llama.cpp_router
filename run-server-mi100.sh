#!/bin/bash
set -euo pipefail
# Primary jukebox launcher: MI100 (card 1) + RX 7900 XTX (card 2).
# Cards 0 and 3 (the R9700 pair) are reserved for vLLM.
# The 16,9 tensor split in models.ini assumes this card order.
IMAGE="${IMAGE:-rocm-llama-cpp:rocm714}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HIP_VISIBLE_DEVICES="${HIP_VISIBLE_DEVICES:-1,2}"
GPU_ENV=(--env "HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES}")
# The image CMD starts llama-server in router (jukebox) mode using models.ini.
# The working-tree models.ini is bind-mounted over the image copy so configuration
# changes take effect on the next launch without an image rebuild.
# --models-max 5 lets the jukebox keep every configured track resident in the
# host page cache; the GGUF files are mmap'ed from the bind-mounted HF cache.
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
  -v "${SCRIPT_DIR}/models.ini:/etc/llama-server/models.ini:ro" \
  "${GPU_ENV[@]}" \
  "${IMAGE}"
