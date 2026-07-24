#!/bin/bash
set -euo pipefail
docker run -it \
  --rm \
  --name rocm-llama \
  --network host \
  --ipc=host \
  --device /dev/kfd \
  --device /dev/dri \
  --group-add video \
  --group-add render \
  --tmpfs /tmp \
  --security-opt no-new-privileges \
  -v ~/.cache/huggingface:/tmp/huggingface \
  -e HF_HOME=/tmp/huggingface \
  --entrypoint /bin/bash \
  rocm-llama-cpp:rocm724
