# Design

## Components

### Dockerfile

```
Base: rocm/pytorch:rocm7.2.2_ubuntu24.04_py3.12_pytorch_release_2.10.0
  → clone llama.cpp @ 63d93d17336e41e4cc73a64452e5b1d2477abdb1
  → cmake -DGGML_HIP=ON -DAMDGPU_TARGETS="gfx908;gfx1100"
  → cmake --build, then cp build/bin/llama-server → /usr/local/bin/llama/llama-server
  → remove models.ini COPY (out of scope)
  → create llama user (video, render groups), home dir /home/llama
  → ENV HF_HOME=/home/llama/.cache/huggingface
  → COPY entrypoint.sh → /usr/local/bin/entrypoint.sh
  → ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
  → CMD ["/usr/local/bin/llama/llama-server", "-fa", "1", "--parallel", "3", ...]
```

CMD carries the full default server invocation. Override CMD at `docker run` to change flags.

Full CMD line:

```dockerfile
CMD ["/usr/local/bin/llama/llama-server", \
     "-fa", "1", "--parallel", "3", "--kv-unified", \
     "-ts", "9/16", "-ctk", "bf16", "-ctv", "bf16", \
     "--hf-repo", "unsloth/Qwen3.6-27B-GGUF:Q8_0", \
     "--temp", "0.6", "--top-p", "0.95", "--top-k", "20", \
     "--min-p", "0.0", "--presence-penalty", "0.0", "--repeat-penalty", "1.0", \
     "--reasoning-budget", "32768", "--ctx-size", "262144", \
     "--host", "0.0.0.0", "--port", "8000"]
```

### entrypoint.sh

```sh
#!/bin/sh
mkdir -p /home/llama/.cache/huggingface
exec "$@"
```

Ensures HF cache dir exists before exec (needed when mount is absent or dir is missing inside the container). Passes CMD through unchanged. No staging logic, no XDG redirects.

### run-server.sh

Single `docker run` invocation:

```sh
docker run \
  --read-only --tmpfs /tmp --no-new-privileges \
  --network host \
  --device /dev/kfd --device /dev/dri \
  --group-add video --group-add render \
  -v "${MODELS_DIR}:/models:ro" \
  -v "${HOME}/.cache/huggingface:/home/llama/.cache/huggingface" \
  rocm-llama-server
```

`MODELS_DIR` set by caller or sourced from `.env` at top of script.

## Deleted Complexity

- No staged progression (stage 1–4)
- No router mode
- No `models.ini` parsing
- No multi-model orchestration
- No XDG redirection to /tmp (HF cache mounted directly to HF_HOME)
