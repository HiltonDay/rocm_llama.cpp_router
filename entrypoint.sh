#!/bin/sh
set -e

# XDG base directory setup - all under /tmp for read-only filesystem compatibility
mkdir -p /tmp/llama-cache /tmp/llama-config /tmp/llama-data
chmod 1777 /tmp/llama-cache /tmp/llama-config /tmp/llama-data

export XDG_CACHE_HOME=/tmp/llama-cache
export XDG_CONFIG_HOME=/tmp/llama-config
export XDG_DATA_HOME=/tmp/llama-data

# If first argument is a shell or --shell, drop to interactive shell as llama user
# This enables debugging: podman run ... --shell  or  podman exec -it ... /bin/sh
if [ "${1:-}" = "--shell" ] || [ "${1:-}" = "sh" ] || [ "${1:-}" = "bash" ]; then
    exec setpriv --reuid=$(id -u llama) --regid=$(id -g llama) --init-groups --inh-caps=-all \
        "$@"
fi

# Default: drop to llama user and run llama-server with all passed arguments
# --init-groups rebuilds supplementary groups from /etc/group (video, render for GPU access)
# --inh-caps=-all drops all inheritable capabilities for security
exec setpriv --reuid=$(id -u llama) --regid=$(id -g llama) --init-groups --inh-caps=-all \
    /usr/local/bin/llama/llama-server "$@"
