#!/bin/bash
mkdir -p /tmp/.cache/llama.cpp
chown -R llama:llama /tmp/.cache
export XDG_CACHE_HOME=/tmp
exec gosu llama "$@"
