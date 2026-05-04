#!/bin/sh
set -e

# ============================================================
# XDG BASE DIRECTORY SETUP
# All under /tmp for read-only filesystem compatibility
# ============================================================
mkdir -p /tmp/llama-cache /tmp/llama-config /tmp/llama-data
chmod 1777 /tmp/llama-cache /tmp/llama-config /tmp/llama-data

export XDG_CACHE_HOME=/tmp/llama-cache
export XDG_CONFIG_HOME=/tmp/llama-config
export XDG_DATA_HOME=/tmp/llama-data

# ============================================================
# STAGE 1: Interactive debug shell
# If first argument is --shell, sh, or bash, drop to shell as llama user
# Usage: docker run ... <image> --shell
# ============================================================
if [ "${1:-}" = "--shell" ] || [ "${1:-}" = "sh" ] || [ "${1:-}" = "bash" ]; then
    exec setpriv --reuid=$(id -u llama) --regid=$(id -g llama) --init-groups --inh-caps=-all \
        "$@"
fi

# ============================================================
# STAGE 2: Keep-alive mode (uncomment for Stage 2)
# Server runs in background; container stays alive for exec debugging
# If server crashes, container remains running for diagnosis
# Usage: docker run ... <image> --keep-alive <server-args...>
# ============================================================
# if [ "${1:-}" = "--keep-alive" ]; then
#     shift  # remove --keep-alive from args
#     setpriv --reuid=$(id -u llama) --regid=$(id -g llama) --init-groups --inh-caps=-all \
#         /usr/local/bin/llama/llama-server "$@" &
#     SERVER_PID=$!
#     echo "llama-server started as PID $SERVER_PID"
#     # Wait for server; if it exits, sleep forever so container stays up for debugging
#     wait $SERVER_PID || true
#     echo "llama-server exited (PID $SERVER_PID). Container staying alive for debugging."
#     echo "Exec in with: docker exec -it <container> /usr/local/bin/entrypoint.sh --shell"
#     tail -f /dev/null
# fi

# ============================================================
# STAGE 3 & 4: Default — drop to llama user and run llama-server
# Arguments come from CMD (Stage 3/4) or docker run (Stage 2 without keep-alive)
# --init-groups rebuilds supplementary groups from /etc/group (video, render)
# --inh-caps=-all drops all inheritable capabilities
# ============================================================
exec setpriv --reuid=$(id -u llama) --regid=$(id -g llama) --init-groups --inh-caps=-all \
    /usr/local/bin/llama/llama-server "$@"
