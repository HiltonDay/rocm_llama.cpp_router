# Requirements: Phase 2 — Router Mode

Phase 1 delivered a working single-model auto-start container. Phase 2 switches to router mode: llama-server loads models on demand from a config file, one at a time, swapping on client request.

No changes to GPU access, security hardening, or mounts — those are proven. Scope: models.ini in the image, CMD flags, nothing else.

---

## REQ-R1: models.ini Embedded in Image

**Description:** The image includes `/etc/llama-server/models.ini` defining all available models. This is the single source of truth for what models the server knows about.

**Acceptance Criteria:**
- `COPY models.ini /etc/llama-server/models.ini` present in Dockerfile
- `docker run --rm <image> cat /etc/llama-server/models.ini` returns the file contents
- File defines at least one model with `hf =` pointing to a valid HuggingFace repo:quant string
- Global defaults in `[*]` section (flash-attn, parallel, tensor-split, cache types)

---

## REQ-R2: Router Mode CMD

**Description:** Dockerfile CMD starts llama-server in router mode using `--models-preset` and `--models-max 1`.

**Acceptance Criteria:**
- CMD uses `--models-preset /etc/llama-server/models.ini --models-max 1 --host 0.0.0.0 --port 8000`
- No hardcoded model path, `--hf-repo`, or per-model sampling flags in CMD
- Container starts without additional arguments via `run-server.sh`
- `docker logs <container>` shows llama-server loading in router/preset mode

---

## REQ-R3: Model Swap on Demand

**Description:** When a client request specifies a model not currently loaded, the server unloads the current model and loads the requested one before responding.

**Acceptance Criteria:**
- POST `/v1/chat/completions` with `"model": "<name>"` for a non-loaded model triggers a swap
- Server responds successfully after swap completes (not an error)
- `docker logs` shows unload of previous model and load of requested model during swap
- Second request to same model does not trigger another swap (already loaded)

---

## REQ-R4: Model Listing

**Description:** GET `/v1/models` returns all models defined in models.ini, regardless of which model is currently loaded.

**Acceptance Criteria:**
- `curl http://localhost:8000/v1/models` returns HTTP 200
- Response JSON `data` array contains one entry per `[section]` in models.ini
- Model IDs match the section headers (e.g. `unsloth/Qwen3.6-27B-GGUF:Q8_0`)
- Response is valid OpenAI-compatible models list format

---

## REQ-R5: Startup Model Pre-Load

**Description:** The model marked `load-on-startup = true` in models.ini is loaded when the server starts, not on first request.

**Acceptance Criteria:**
- `docker logs <container>` shows the startup model loading before any client request
- First request to the startup model does not incur a swap delay
- Currently: `unsloth/Qwen3.6-27B-GGUF:Q8_0` is the startup model (as set in models.ini)
