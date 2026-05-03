#!/bin/sh
set -e

mkdir -p /tmp/llama-cache
chmod 1777 /tmp/llama-cache
export XDG_CACHE_HOME=/tmp/llama-cache

# Drop to llama user and run the server
# --init-groups rebuilds supplementary groups from /etc/group (video, render for GPU access)
exec setpriv --reuid=$(id -u llama) --regid=$(id -g llama) --init-groups --inh-caps=-all \
    /usr/local/bin/llama/llama-server "$@"
