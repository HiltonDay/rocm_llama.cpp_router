#!/bin/sh
set -e

mkdir -p /tmp/llama-cache
chmod 1777 /tmp/llama-cache
export LLAMA_CACHE=/tmp/llama-cache
export HF_HUB_CACHE=/huggingface/hub

# Drop to nobody and run the server
exec setpriv --reuid=nobody --regid=nogroup --clear-groups --inh-caps=-all \
    /usr/local/bin/llama/llama-server "$@"
