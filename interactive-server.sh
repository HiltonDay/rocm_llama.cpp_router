#!/bin/bash
set -euo pipefail

# Interactive shell for manual llama-server/llama-bench usage.
# Uses the entrypoint.sh for privilege drop (gosu llama), then runs bash.

IMAGE="${IMAGE:-rocm-llama-cpp:rocm714}"
HOME_VOLUME="${HOME_VOLUME:-rocm-llama-home}"
CONTAINER_NAME="${CONTAINER_NAME:-rocm-llama-interactive}"
NETWORK="${NETWORK:-host}"
PUBLISH_ARGS=()
if [[ -n "${HOST_PORT:-}" ]]; then
  if [[ "$NETWORK" == "host" ]]; then
    printf 'HOST_PORT requires a non-host NETWORK\n' >&2
    exit 2
  fi
  PUBLISH_ARGS+=(--publish "127.0.0.1:${HOST_PORT}:8000")
fi
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
# The default host network preserves local API reachability. NETWORK can select
# a user-defined bridge for named peer-container access.
# --ipc=host preserves shared-memory use.
# --device and --group-add expose ROCm device nodes to the non-root llama user.
# --tmpfs supplies volatile, non-executable runtime cache space without persistence.
# no-new-privileges blocks privilege escalation.
# The named home volume persists Bash history and other interactive state.
# The Hugging Face cache bind mount remains separate and read-write.

docker run "${RUN_MODE[@]}" \
  --rm \
  --name "$CONTAINER_NAME" \
  --network "$NETWORK" \
  "${PUBLISH_ARGS[@]}" \
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
