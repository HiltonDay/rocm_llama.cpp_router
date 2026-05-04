# TEST_PLAYBOOK.md — ROCm llama.cpp Router Server

Complete manual verification for all four stages. Follow sequentially — each stage must pass before progressing.

## Pre-Flight Checklist

Verify all prerequisites before starting any stage.

### Check ROCm Driver

```bash
rocminfo | head -20
```

**Expected:** Output contains "HSA Runtime" and agent entries listing your GPU.

**If it fails:** ROCm driver not installed or not loaded. Install ROCm drivers for your distro.

### Check Docker

```bash
docker --version
```

**Expected:** Version 20 or higher.

**If it fails:** Install Docker. Ensure the Docker service is running.

### Check GPU Devices

```bash
ls -la /dev/kfd /dev/dri/render*
```

**Expected:** Device nodes exist with correct permissions (crw-rw----).

**If it fails:** GPU devices not accessible. Check that your user is in the `video` and `render` groups on the host.

### Check HF Cache Exists

```bash
ls ~/.cache/huggingface/hub/ | head -5
```

**Expected:** Model cache directories listed.

**If it fails:** Models not pre-downloaded. Follow the Pre-download Models section in README.md.

### Check Models Downloaded

Run one command per model — expect count > 0 for each:

```bash
ls ~/.cache/huggingface/hub/models--unsloth--Qwen3.6-27B-GGUF/blobs/ | wc -l
ls ~/.cache/huggingface/hub/models--unsloth--gemma-4-31B-it-GGUF/blobs/ | wc -l
ls ~/.cache/huggingface/hub/models--unsloth--Qwen3.6-35B-A3B-GGUF/blobs/ | wc -l
ls ~/.cache/huggingface/hub/models--unsloth--gemma-4-26B-A4B-it-GGUF/blobs/ | wc -l
```

**Expected:** Each returns a number > 0.

**If it fails:** Model not fully downloaded. Re-run the `hf download` command for the missing model.

### Check Image Built

```bash
docker images llama-cpp-server
```

**Expected:** Image listed with a recent build timestamp.

**If it fails:** Build the image:

```bash
docker build -t llama-cpp-server .
```

---

## Stage 1: Interactive Debug Image

Stage 1 is the default — `run-server.sh` launches with `--shell` and no code changes needed.

### Launch

```bash
./run-server.sh
```

This runs `docker run -it ... --shell`, dropping you into an interactive shell inside the container as the `llama` user.

### Verification Steps

#### 1.1 Verify you're the llama user

```bash
id
```

**Expected:** `uid=...(llama) gid=...(llama) groups=...(llama),video,render`

**If it fails:** User setup in Dockerfile is broken.

#### 1.2 Verify GPU device access

```bash
ls -la /dev/kfd /dev/dri/render*
```

**Expected:** Readable device nodes.

**If it fails:** Check `--device` and `--group-add` flags in run-server.sh.

#### 1.3 Verify environment variables

```bash
env | grep -E '(XDG|LD_LIBRARY|HF_HOME)'
```

**Expected:**
- `XDG_CACHE_HOME=/tmp/llama-cache`
- `XDG_CONFIG_HOME=/tmp/llama-config`
- `XDG_DATA_HOME=/tmp/llama-data`
- `LD_LIBRARY_PATH` contains `/usr/local/bin/llama`
- `HF_HOME=/huggingface`

**If it fails:** Check Dockerfile ENV and entrypoint.sh exports.

#### 1.4 Verify HF cache mount

```bash
ls /huggingface/hub/ | head -5
```

**Expected:** Model cache directories.

**If it fails:** Check bind mount in run-server.sh. Verify host HF cache path.

#### 1.5 Verify models mount

```bash
ls /models/
```

**Expected:** Directory listing (may be empty if no models placed there).

**If it fails:** Check bind mount in run-server.sh.

#### 1.6 Verify library path

```bash
ls /usr/local/bin/llama/llama-server
```

**Expected:** File exists.

**If it fails:** Dockerfile build didn't copy the binary correctly.

#### 1.7 Verify shared libraries

```bash
ldd /usr/local/bin/llama/llama-server | grep "not found"
```

**Expected:** No output (all libraries found).

**If it fails:** Missing shared libraries. Check Dockerfile library copy step.

#### 1.8 Verify writable tmp

```bash
touch /tmp/test && rm /tmp/test
```

**Expected:** No error.

**If it fails:** tmpfs mount not configured correctly.

#### 1.9 Verify read-only filesystem

```bash
touch /test 2>&1
```

**Expected:** `Read-only file system`

**If it fails:** `--read-only` flag not applied.

#### 1.10 Manual server start

```bash
/usr/local/bin/llama/llama-server --model hf=unsloth/Qwen3.6-27B-GGUF:Q8_0 --host 127.0.0.1 --port 8000 --ctx-size 4096 --flash-attn
```

**Expected:** Server startup logs showing GPU detection and model loading.

**If it fails:** Check GPU access, library paths, and model availability.

#### 1.11 HTTP test (from another terminal on host)

```bash
curl http://127.0.0.1:8000/v1/models
```

**Expected:** JSON response with model name.

**If it fails:** Server didn't start correctly or port binding failed.

#### 1.12 Stop server

Press Ctrl+C in the container shell.

#### 1.13 Exit container

```bash
exit
```

### Stage Gate 1 Checklist

- [ ] All 9 environment checks (1.1–1.9) pass
- [ ] Manual server starts and loads model (1.10)
- [ ] HTTP endpoint responds (1.11)

---

## Stage 2: Script-Initiated Server with Debug Access

### Progression Instructions

1. In `run-server.sh`: Comment out the Stage 1 block (add `#` to the `docker run -it` lines, ~39-52). Uncomment the Stage 2 block (remove `#` from the `docker run -d` lines, ~59-76).
2. In `entrypoint.sh`: Uncomment the `--keep-alive` block (remove `# ` from lines 31-42).
3. No Dockerfile changes needed.
4. No image rebuild needed.

### Launch

```bash
./run-server.sh
```

This runs Stage 2 detached with `--keep-alive`.

### Verification Steps

#### 2.1 Verify container running

```bash
docker ps --filter name=llama-server
```

**Expected:** Container listed with status "Up".

**If it fails:** Check `docker logs llama-server` for errors.

#### 2.2 Verify server logs

```bash
docker logs llama-server
```

**Expected:** "llama-server started as PID" message followed by model loading logs.

**If it fails:** `--keep-alive` block not uncommented in entrypoint.sh.

#### 2.3 Wait for model load

```bash
docker logs -f llama-server
```

**Expected:** "model loaded" or similar message, then Ctrl+C.

#### 2.4 HTTP test

```bash
curl http://127.0.0.1:8000/v1/models
```

**Expected:** JSON response with model name.

**If it fails:** Server hasn't finished loading yet. Wait and retry.

#### 2.5 Chat completion test

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"unsloth/Qwen3.6-27B-GGUF:Q8_0","messages":[{"role":"user","content":"Say hello in one word"}]}'
```

**Expected:** JSON response with completion.

#### 2.6 Exec into running container

```bash
docker exec -it llama-server /usr/local/bin/entrypoint.sh --shell
```

**Expected:** Shell prompt as llama user.

**If it fails:** Container not running or entrypoint.sh not accessible.

#### 2.7 Inside exec shell — verify environment

```bash
env | grep -E '(XDG|LD_LIBRARY|HF_HOME)'
```

**Expected:** Same variables as Stage 1.

#### 2.8 Inside exec shell — verify server process

```bash
ps aux | grep llama-server
```

**Expected:** llama-server process running as llama user.

#### 2.9 Inside exec shell — check GPU memory

```bash
cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null || echo "check rocm-smi on host"
```

**Expected:** Non-zero VRAM usage.

#### 2.10 Exit exec shell

```bash
exit
```

#### 2.11 Stop container

```bash
docker stop llama-server && docker rm llama-server
```

### Keep-Alive Test (Optional)

Kill the server process inside the container to verify the container stays alive:

```bash
docker exec llama-server kill $(docker exec llama-server pgrep llama-server)
docker logs llama-server | tail -5
```

**Expected:** "llama-server exited... Container staying alive for debugging"

```bash
docker ps --filter name=llama-server
```

**Expected:** Container still running.

### Stage Gate 2 Checklist

- [ ] Container starts detached and stays running
- [ ] Server loads model successfully
- [ ] HTTP endpoint responds
- [ ] Chat completion works
- [ ] Exec debugging works
- [ ] Logs accessible via `docker logs`

---

## Stage 3: Auto-Start Server Image

### Progression Instructions

1. In `Dockerfile`: Uncomment the Stage 3 CMD block (remove `# ` from lines 66-69). Keep Stage 4 CMD commented.
2. In `run-server.sh`: Comment out Stage 2 block. Uncomment Stage 3 block.
3. In `entrypoint.sh`: No changes needed (keep-alive block can stay uncommented or be re-commented — it won't trigger because Stage 3 doesn't pass `--keep-alive`).
4. **Rebuild image:** `docker build -t llama-cpp-server .`

### Launch

```bash
./run-server.sh
```

This runs Stage 3 — no extra args, CMD provides them.

### Verification Steps

#### 3.1 Verify container running

```bash
docker ps --filter name=llama-server
```

**Expected:** Container listed.

**If it fails:** Check `docker logs llama-server` for errors.

#### 3.2 Verify auto-start in logs

```bash
docker logs llama-server
```

**Expected:** llama-server startup without any "keep-alive" messages (direct exec, not backgrounded).

#### 3.3 Wait for model load

```bash
docker logs -f llama-server
```

**Expected:** Model loaded message.

#### 3.4 HTTP test

```bash
curl http://127.0.0.1:8000/v1/models
```

**Expected:** JSON with model.

#### 3.5 Stop/start cycle

```bash
docker stop llama-server && docker start llama-server
```

**Expected:** Container restarts.

#### 3.6 Wait for reload

```bash
sleep 30 && curl http://127.0.0.1:8000/v1/models
```

**Expected:** JSON response (server auto-restarted).

#### 3.7 Verify logs after restart

```bash
docker logs --since 1m llama-server
```

**Expected:** Fresh startup sequence.

#### 3.8 Exec debug access

```bash
docker exec -it llama-server /usr/local/bin/entrypoint.sh --shell
```

**Expected:** Shell prompt.

#### 3.9 Inside exec — verify server

```bash
ps aux | grep llama-server
```

**Expected:** Process running.

#### 3.10 Exit and cleanup

```bash
exit
docker stop llama-server && docker rm llama-server
```

### Stage Gate 3 Checklist

- [ ] Auto-starts on container launch
- [ ] Stop/start cycle works
- [ ] HTTP responds after restart
- [ ] Exec debugging works
- [ ] Logs show direct exec (no keep-alive messages)

---

## Stage 4: Production Router Mode

### Progression Instructions

1. In `Dockerfile`: Comment out Stage 3 CMD. Uncomment Stage 4 CMD block (lines 74-76).
2. In `run-server.sh`: Comment out Stage 3 block. Uncomment Stage 4 block. (Note: Stage 3 and 4 docker run blocks are identical — the difference is the Dockerfile CMD.)
3. **Rebuild image:** `docker build -t llama-cpp-server .`

### Launch

```bash
./run-server.sh
```

### Verification Steps

#### 4.1 Verify container running

```bash
docker ps --filter name=llama-server
```

**Expected:** Container listed.

#### 4.2 Verify router mode in logs

```bash
docker logs llama-server
```

**Expected:** "models-preset" or INI loading messages.

#### 4.3 List all models

```bash
curl http://127.0.0.1:8000/v1/models
```

**Expected:** JSON listing all 4 models from models.ini.

#### 4.4 Chat with startup model

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"unsloth/Qwen3.6-27B-GGUF:Q8_0","messages":[{"role":"user","content":"Say hello in one word"}]}'
```

**Expected:** Completion response.

#### 4.5 Model swap test

```bash
time curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"unsloth/gemma-4-31B-it-GGUF:Q8_0","messages":[{"role":"user","content":"Say hello in one word"}]}'
```

**Expected:** Completion response; `time` shows swap duration (expect 3-10 seconds for first request to new model).

#### 4.6 Verify swap in logs

```bash
docker logs --since 2m llama-server | grep -i "unload\|load\|swap"
```

**Expected:** Unload/load messages.

#### 4.7 Error handling — unknown model

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"nonexistent/model","messages":[{"role":"user","content":"test"}]}'
```

**Expected:** Error response (HTTP 400 or 404).

#### 4.8 Second swap — back to original

```bash
time curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"unsloth/Qwen3.6-27B-GGUF:Q8_0","messages":[{"role":"user","content":"Confirm swap back"}]}'
```

**Expected:** Completion; timing shows swap.

#### 4.9 Exec debug access

```bash
docker exec -it llama-server /usr/local/bin/entrypoint.sh --shell
```

**Expected:** Shell prompt.

#### 4.10 Cleanup

```bash
exit
docker stop llama-server && docker rm llama-server
```

### Stage Gate 4 Checklist

- [ ] Router mode starts
- [ ] All 4 models listed
- [ ] Chat works with startup model
- [ ] Model swap works within expected timing
- [ ] Unknown model returns error
- [ ] Swap back to original model works
- [ ] Exec debugging works

---

## Troubleshooting

### GPU Device Permission Errors

**Symptom:** `/dev/kfd: Permission denied` or server can't detect GPU.

**Diagnostics:**
```bash
# On host:
ls -la /dev/kfd /dev/dri/render*
# Check user groups:
groups
# Inside container:
docker exec llama-server id
docker exec llama-server ls -la /dev/kfd /dev/dri/render*
```

**Resolution:** Ensure host user is in `video` and `render` groups. Verify `--device` and `--group-add` flags in docker run.

### Library Path Issues

**Symptom:** `libhiprtc.so: cannot open shared object` or similar.

**Diagnostics:**
```bash
docker exec llama-server ldd /usr/local/bin/llama/llama-server | grep "not found"
docker exec llama-server env | grep LD_LIBRARY_PATH
```

**Resolution:** Verify `LD_LIBRARY_PATH` includes `/usr/local/bin/llama`. Check library files exist in the image.

### Mount Permission Errors

**Symptom:** Permission denied when accessing `/huggingface` or `/models`.

**Diagnostics:**
```bash
docker exec llama-server ls -la /huggingface /models
docker exec llama-server id
```

**Resolution:** Check SELinux labels (`,z`). Check host directory permissions.

### Port Binding Failures

**Symptom:** `bind: Address already in use`.

**Diagnostics:**
```bash
lsof -i :8000
ss -tlnp | grep 8000
```

**Resolution:** Another process is using port 8000. Stop it or use a different port.

### Server Crash Diagnosis

**Symptom:** Container exits or server stops responding.

**Diagnostics:**
```bash
docker logs llama-server
docker inspect llama-server --format '{{.State.ExitCode}}'
```

**Resolution:** Check for OOM (model too large for VRAM), GPU architecture mismatch, or `--ctx-size` too large.

### Model Loading Failures

**Symptom:** Server can't find model files.

**Diagnostics:**
```bash
# On host:
ls ~/.cache/huggingface/hub/models--<org>--<model>/
# Inside container:
docker exec llama-server ls /huggingface/hub/
docker exec llama-server env | grep HF_HOME
```

**Resolution:** Verify model exists in HF cache. Check model format is GGUF. Verify `HF_HOME` env var inside container.

### Container Exits Immediately

**Symptom:** Container starts then stops within seconds.

**Diagnostics:**
```bash
docker inspect llama-server --format '{{.State.ExitCode}}'
docker logs llama-server
```

**Resolution:** Common causes: missing GPU, wrong architecture, permission denied on devices.

### Read-Only Filesystem Errors

**Symptom:** `Read-only file system` errors during server operation.

**Diagnostics:**
```bash
docker exec llama-server mount | grep tmpfs
docker exec llama-server env | grep XDG
```

**Resolution:** Verify tmpfs mount at /tmp. Check XDG vars point to /tmp subdirs. Verify entrypoint.sh creates dirs before server starts.

---

## Stage Progression Reference

| From → To | Dockerfile | entrypoint.sh | run-server.sh | Rebuild needed? |
|-----------|-----------|---------------|---------------|-----------------|
| Stage 1 → 2 | No change | Uncomment `--keep-alive` block (lines 31-42) | Comment Stage 1, uncomment Stage 2 | No |
| Stage 2 → 3 | Uncomment Stage 3 CMD (lines 66-69) | No change | Comment Stage 2, uncomment Stage 3 | Yes |
| Stage 3 → 4 | Comment Stage 3 CMD, uncomment Stage 4 CMD (lines 74-76) | No change | Comment Stage 3, uncomment Stage 4 | Yes |

**Important:** Only one stage's docker run block should be active in run-server.sh. Only one CMD block should be uncommented in Dockerfile (for Stages 3-4).
