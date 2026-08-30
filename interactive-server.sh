#!/bin/bash
set -euo pipefail

# Interactive shell for manual llama-server/llama-bench usage.
# Uses the entrypoint.sh for privilege drop (gosu llama), then runs bash.

IMAGE="rocm-llama-cpp:rocm724"

# --rm prevents discarded debug containers from accumulating.
# --network/--ipc host preserve local API reachability and permit shared-memory use.
# --device and --group-add expose ROCm device nodes to the non-root llama user.
# --tmpfs supplies volatile, non-executable runtime cache space without persistence.
# no-new-privileges blocks privilege escalation; the writable image layer is intentional
# for interactive debugging, unlike the read-only production launcher.
# The Hugging Face cache mount is read-write so hf tools can download missing models.

docker run -it \
  --rm \
  --name rocm-llama-interactive \
  --network host \
  --ipc=host \
  --device /dev/kfd \
  --device /dev/dri \
  --group-add video \
  --group-add render \
  --tmpfs /tmp:rw,noexec,nosuid,size=512m \
  --security-opt no-new-privileges \
  -v "${HOME}/.cache/huggingface:/home/llama/.cache/huggingface" \
  "${IMAGE}" \
  /bin/bash
