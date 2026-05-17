# Design: Phase 2 — Router Mode

## Summary

Two file changes: Dockerfile gets a `COPY` and a new CMD. models.ini is validated/refined. entrypoint.sh and run-server.sh are unchanged.

llama-server's `--models-preset` flag handles all routing internally — no application-level dispatch code.

---

## models.ini Format

llama-server's INI parser expects:

```ini
version = 1

[*]
# Global defaults applied to all models
flash-attn = 1
parallel = 3
tensor-split = 12/19
cache-type-k = bf16
cache-type-v = bf16

[unsloth/Qwen3.6-27B-GGUF:Q8_0]
# Section header becomes the model ID in /v1/models and in client requests
load-on-startup = true
hf = unsloth/Qwen3.6-27B-GGUF:Q8_0
temp = 0.6
top-p = 0.95
top-k = 20
min-p = 0.0
ctx-size = 262144

[unsloth/gemma-4-31B-it-GGUF:Q8_0]
hf = unsloth/gemma-4-31B-it-GGUF:Q8_0
temp = 1.0
top-p = 0.95
top-k = 64
ctx-size = 196608
```

The existing `rocm_docker/models.ini` already matches this format. Task 1 is a review pass, not a rewrite.

**Key rules:**
- Section header = model ID (clients use this string in `"model": "..."`)
- `hf =` value must be `repo:quant` for HuggingFace download
- `load-on-startup = true` on exactly one model (the default/startup model)
- `[*]` section sets shared defaults; per-model sections override

---

## Dockerfile Changes

**Add** before ENTRYPOINT:
```dockerfile
COPY models.ini /etc/llama-server/models.ini
```

**Replace** current CMD:
```dockerfile
# Before (Phase 1 — single model hardcoded):
CMD ["/usr/local/bin/llama/llama-server", "-fa", "1", "-ts", "9/16", "-ctk", "bf16", \
     "-ctv", "bf16", "--hf-repo", "unsloth/Qwen3.6-27B-GGUF:Q8_0", ...]

# After (Phase 2 — router mode):
CMD ["/usr/local/bin/llama/llama-server", \
     "--models-preset", "/etc/llama-server/models.ini", \
     "--models-max", "1", \
     "--host", "0.0.0.0", \
     "--port", "8000"]
```

All per-model parameters (flash-attn, ctx-size, temp, etc.) move from CMD into models.ini where they belong.

---

## entrypoint.sh — Unchanged

Current entrypoint does:
1. `mkdir -p /tmp/.cache/llama.cpp`
2. `chown -R llama:llama /tmp/.cache`
3. `export XDG_CACHE_HOME=/tmp`
4. `exec gosu llama "$@"`

This works for router mode. `"$@"` passes CMD args through. No changes needed.

---

## run-server.sh — Unchanged

Current script does `docker run -d ... rocm-llama` with no extra arguments — CMD provides them. This continues to work unchanged. The only difference is what CMD does, which is internal to the image.

---

## How Router Mode Works

```
Client: POST /v1/chat/completions {"model": "unsloth/gemma-4-31B-it-GGUF:Q8_0", ...}
  └─> llama-server checks: is gemma loaded? No.
      └─> Unload current model (Qwen3.6-27B)
      └─> Load gemma-4-31B (downloads from HF cache if needed)
      └─> Process request
      └─> Return response

Client: GET /v1/models
  └─> llama-server reads models.ini
  └─> Returns all section headers as model list (regardless of which is loaded)
```

`--models-max 1` enforces single-model VRAM usage. Swap is sequential: unload completes before load begins.

---

## What Does Not Change

| Component | Status | Reason |
|-----------|--------|--------|
| `entrypoint.sh` | Unchanged | `exec gosu llama "$@"` passes CMD through cleanly |
| `run-server.sh` | Unchanged | Still `docker run -d ... rocm-llama` with no extra args |
| GPU device mounts | Unchanged | `--device /dev/kfd`, `--device /dev/dri` stay in run-server.sh |
| Security hardening | Unchanged | read-only FS, tmpfs, no-new-privileges all stay |
| HF cache mount | Unchanged | Models still come from `~/.cache/huggingface` |
| Image build (ROCm/HIP) | Unchanged | Same base image, same llama.cpp commit, same compile flags |
