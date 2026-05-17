#!/bin/bash
podman run -d \
  --rm \
  --name rocm-llama \
  --network host \
  --device /dev/kfd \
  --device /dev/dri \
  --group-add video \
  --group-add render \
  --read-only \
  --tmpfs /tmp \
  --security-opt no-new-privileges \
  -v ~/.cache/huggingface:/tmp/huggingface \
  -e HF_HOME=/tmp/huggingface \
  rocm-llama
