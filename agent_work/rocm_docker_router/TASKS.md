# Tasks: Phase 2 — Router Mode

Sequential. Each task depends on the prior.

---

## TASK-R1: Review and Validate models.ini

**Owner:** agent
**Input:** `rocm_docker/models.ini`
**Deliverable:** Validated (or corrected) `rocm_docker/models.ini`

Check:
- `version = 1` present at top
- `[*]` section has global defaults matching current CMD flags (`flash-attn`, `parallel`, `tensor-split`, `cache-type-k`, `cache-type-v`)
- Each model section has `hf =` in `repo:quant` format
- Exactly one model has `load-on-startup = true`
- No stray keys llama-server won't recognise
- Section headers are valid model IDs (clients will use these strings verbatim)

Current file already looks correct — this is a review pass, not a rewrite. Edit only if something is wrong.

**Done when:** File reviewed, any issues fixed, format confirmed against llama-server `--models-preset` docs.

---

## TASK-R2: Update Dockerfile

**Owner:** agent
**Input:** `rocm_docker/Dockerfile`, validated `models.ini`
**Deliverable:** Updated `rocm_docker/Dockerfile`

Two changes only:

1. Add after the `COPY entrypoint.sh` line:
   ```dockerfile
   COPY models.ini /etc/llama-server/models.ini
   ```

2. Replace the `CMD` line with:
   ```dockerfile
   CMD ["/usr/local/bin/llama/llama-server", \
        "--models-preset", "/etc/llama-server/models.ini", \
        "--models-max", "1", \
        "--host", "0.0.0.0", \
        "--port", "8000"]
   ```

No other changes. Do not touch the build section, user setup, entrypoint, or ENV vars.

**Done when:** `git diff rocm_docker/Dockerfile` shows exactly these two changes and nothing else.

---

## TASK-R3: Rebuild and Test

**Owner:** person (requires GPU hardware)
**Input:** Updated Dockerfile, validated models.ini
**Deliverable:** Verified running container in router mode

### Build
```bash
cd rocm_docker
docker build -t rocm-llama .
```

### Start
```bash
./run-server.sh
```

### Verify model listing (REQ-R4)
```bash
curl -s http://localhost:8000/v1/models | jq '.data[].id'
```
Expected: one line per model section in models.ini.

### Verify startup model loaded (REQ-R5)
```bash
docker logs rocm-llama | grep -i "load"
```
Expected: startup model (`unsloth/Qwen3.6-27B-GGUF:Q8_0`) appears in logs before any request.

### Test chat with startup model (baseline)
```bash
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "unsloth/Qwen3.6-27B-GGUF:Q8_0", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 10}' \
  | jq '.choices[0].message.content'
```
Expected: short response, no error.

### Test model swap (REQ-R3)
```bash
time curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "unsloth/gemma-4-31B-it-GGUF:Q8_0", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 10}' \
  | jq '.choices[0].message.content'
```
Expected: successful response after swap delay (3–60s depending on model size). `docker logs` shows unload + load sequence.

### Verify swap does not repeat
```bash
# Second request to gemma — should be fast (no swap)
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "unsloth/gemma-4-31B-it-GGUF:Q8_0", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 10}' \
  | jq '.choices[0].message.content'
```

**Done when:** All five checks above pass.
