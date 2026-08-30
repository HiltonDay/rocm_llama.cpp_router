#!/bin/bash
set -euo pipefail

# Interactive shell for manual llama-server/llama-bench usage.
# Uses the entrypoint.sh for privilege drop (gosu llama), then runs bash.

IMAGE="${IMAGE:-rocm-llama-cpp:rocm714}"
HOME_VOLUME="${HOME_VOLUME:-rocm-llama-home}"
GPU_ENV=()
if [[ -n "${HIP_VISIBLE_DEVICES:-}" ]]; then
  GPU_ENV+=(--env "HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES}")
fi

case "${1:-}" in
  '')
    RUN_MODE=(-it)
    CONTAINER_COMMAND=(/bin/bash)
    ;;
  --detach)
    RUN_MODE=(-d)
    CONTAINER_COMMAND=(sleep infinity)
    ;;
  *)
    printf 'Usage: %s [--detach]\n' "$0" >&2
    exit 2
    ;;
esac

# --rm removes the interactive container after Bash exits or it is stopped.
# --network/--ipc host preserve local API reachability and shared-memory use.
# --device and --group-add expose ROCm device nodes to the non-root llama user.
# --tmpfs supplies volatile, non-executable runtime cache space without persistence.
# no-new-privileges blocks privilege escalation.
# The named home volume persists Bash history and other interactive state.
# The Hugging Face cache bind mount remains separate and read-write.

docker run "${RUN_MODE[@]}" \
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
  --volume "${HOME_VOLUME}:/home/llama" \
  --volume "${HOME}/.cache/huggingface:/home/llama/.cache/huggingface" \
  "${GPU_ENV[@]}" \
  "${IMAGE}" \
  "${CONTAINER_COMMAND[@]}"
