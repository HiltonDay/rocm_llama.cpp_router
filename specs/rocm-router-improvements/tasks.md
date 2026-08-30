# Implementation Plan: ROCm Docker for 4-GPU Mixed Architecture

## Overview

Add gfx1201 (RDNA4 / R9700) support to the existing Docker environment that already works with gfx908 (MI100) + gfx1100 (7900 XTX). Deliver a working interactive Docker environment first, then progress to jukebox (router) mode. Target: 4 GPUs, 3 architectures, ~120GB VRAM.

## Phase 1: Interactive Docker (Priority)

- [ ] 1. Add gfx1201 to Dockerfile build targets and update to latest stable commit
  - **File:** `Dockerfile`
  - **Changes:**
    - `LLAMACPP_ROCM_ARCH` updated to `"gfx908,gfx1100,gfx1201"`
    - `LLAMA_CPP_COMMIT` updated to `b10106` (latest stable release, includes MTP merged at b9235)
  - **Already done.** Verify: `docker build -t rocm-llama-cpp:rocm724 .` completes without HIP compile errors for gfx1201
  - **Note:** Build time increases with 3 targets. Users with only R9700 can set to just `"gfx1201"` for faster builds.
  - **Base image:** Staying on `rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0` (stable). ROCm 7.14/TheRock images exist but are new preview, 18GB, datacenter-focused.
  - _Requirements: 1.1, 1.2_

- [ ] 2. Update interactive-server.sh for production use
  - **File:** `interactive-server.sh`
  - **Changes:**
    - Add `set -euo pipefail` (already present)
    - Update image name to match `rocm-llama-cpp:rocm724` (currently correct)
    - Add `--tmpfs /tmp:rw,noexec,nosuid,size=256m` (increase from default for model cache)
    - Verify HF_HOME mount path aligns with entrypoint expectations
    - Add comment documenting what each flag does
  - **Verify:** `./interactive-server.sh` drops into a shell where `id` shows video/render groups and `/dev/kfd` is accessible
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [ ] 3. Verify GPU access and llama-server functionality inside container
  - **Manual test sequence (to be documented in TEST_PLAYBOOK.md):**
    1. Run `./interactive-server.sh`
    2. Inside container: `id` → confirm llama user with video,render groups
    3. `ls -la /dev/kfd /dev/dri/` → confirm device access
    4. `llama-server --version` or `llama-server --help` → confirm binary works
    5. `llama-bench --help` → confirm bench binary works
    6. `ls $HF_HOME/hub/` → confirm models visible
    7. Start server with small context for quick test:
       ```
       llama-server --model hf=unsloth/Qwen3.6-27B-GGUF:Q8_0 \
         --host 0.0.0.0 --port 8000 --ctx-size 4096 --flash-attn -ngl 99
       ```
    8. From host: `curl http://localhost:8000/v1/models` → confirm response
  - **This task produces the test procedure, not code changes**
  - _Requirements: 2.5, 2.6, 2.7_

- [ ] 4. Update README.md with gfx1201 info and performance notes
  - **File:** `README.md`
  - **Changes:**
    - Update "GPU targets" to include gfx1201
    - Add "Hardware" section documenting R9700 specs and known characteristics
    - Add "Performance Tuning" section with ASPM, bench flags, MTP references
    - Add note about Vulkan vs HIP tradeoff with link to Discussion #21043
    - Update Prerequisites to mention R9700/RDNA4
    - Keep existing sections (Models, Build, Usage, API, Security) updated as needed
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_

- [ ] 5. Create/update TEST_PLAYBOOK.md for Phase 1
  - **File:** `TEST_PLAYBOOK.md`
  - **Content:**
    - Pre-flight: check GPU (rocminfo or ls /dev/kfd), Docker installed, models downloaded, image built
    - Interactive shell verification: all checks from task 3
    - Benchmark execution: llama-bench with recommended flags
    - **Dual R9700 use case:** tensor-split mode, single vs dual comparison, MTP test, known limitations
    - Dual-GPU test (if both cards present): tensor-split, HIP_VISIBLE_DEVICES
    - Troubleshooting: permission errors, library issues, model not found, OOM
  - **Already done.** Dual R9700 section added with UC.1-UC.6 test steps.
  - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [ ] 6. Phase 1 Checkpoint
  - Build the image with gfx1201
  - Run interactive shell
  - Confirm GPU detection (rocm-smi or hipInfo if available, or llama-server GPU detection in logs)
  - Confirm llama-bench runs
  - Confirm manual server start and HTTP response
  - Ask user to verify on their hardware

## Phase 2: Jukebox Mode (Router)

- [ ] 7. Fix run-server.sh security: bind to localhost
  - **File:** `run-server.sh`
  - **Changes:**
    - Image name alignment with build
    - Document security flags inline
    - Note: the CMD in Dockerfile uses `--host 0.0.0.0` — change to `--host 127.0.0.1` for localhost-only
    - Or: override CMD from run-server.sh by appending args
  - **Note on MTP vs Parallel:** Jukebox mode uses `--parallel 3` for multi-user serving. MTP requires `--parallel 1`. These are mutually exclusive. Jukebox mode prioritizes multi-user over MTP speed.
  - _Requirements: 5.1, 5.2_

- [ ] 8. Update Dockerfile CMD for localhost binding
  - **File:** `Dockerfile`
  - **Change:** CMD `--host 0.0.0.0` → `--host 127.0.0.1`
  - **Rebuild required**
  - _Requirements: 5.2_

- [ ] 9. Verify jukebox mode end-to-end
  - **Test sequence:**
    1. `./run-server.sh` → container starts detached
    2. `docker logs rocm-llama` → server starting, model loading
    3. `curl http://localhost:8000/v1/models` → all 4 models listed
    4. Chat completion request → response received
    5. Request different model → swap occurs, response received
    6. `./stop-server.sh` → container stops
  - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [ ] 10. Update TEST_PLAYBOOK.md for Phase 2
  - Add jukebox mode verification section
  - Add model swap timing test
  - Add error handling test (unknown model)
  - _Requirements: 7.1, 7.2_

## Review Findings

### Verdict: REVISE

Task list is mostly sound but has gaps and ambiguities that must be addressed before implementation.

---

### 1. Requirement Coverage

| Req | Covered | Gap |
|-----|---------|-----|
| 1.1 | ✓ | gfx908+gfx1100+gfx1201 in task 1 |
| 1.2 | ✓ | ROCm 7.2.4 base in task 1 |
| 1.3 | ✗ | **Non-root user with video/render groups — no task verifies this in Dockerfile** |
| 1.4 | ✓ | Binaries implied by task 1, but LLAMA_CURL+OPENSSL not explicit |
| 1.5 | ✗ | **LD_LIBRARY_PATH, HF_HOME, PATH — no task sets or verifies these env vars** |
| 1.6 | ✗ | **huggingface_hub and hf_transfer — no task installs these packages** |
| 1.7 | ✓ | b10106 pinned in task 1 |
| 2.1-2.5 | ✓ | Task 2, 3 cover |
| 2.6 | ✓ | GPU detection in task 3 |
| 2.7 | ✓ | llama-bench in task 3 |
| 2.8 | ✓ | HIP_VISIBLE_DEVICES/tensor-split in task 3 |
| 2.9 | ✓ | MTP test in task 5 (TEST_PLAYBOOK.md) |
| 3.1-3.4 | ✓ | Multi-GPU covered in task 3, 5 |
| 3.5-3.6 | ✗ | **4-GPU documentation and tensor-split ratios for 4-GPU missing** |
| 4.1 | ✓ | models-preset in task 9 |
| 4.2 | ✓ | Model swap in task 9 |
| 4.3 | ✓ | GET /v1/models in task 9 |
| 4.4 | ✓ | Swap timing in task 10 |
| 4.5 | ✓ | Security hardening in task 7 |
| 4.6 | ✗ | **stop-server.sh exists but no task verifies it works** |
| 4.7 | ✗ | **models.ini configurability — no task documents how users customize it** |
| 5.1-5.2 | ✓ | Tasks 7, 8 cover |
| 5.3 | ✗ | **Model directories mounted read-only — no task addresses this** |
| 5.4 | ✗ | **gosu privilege drop — no task verifies entrypoint.sh uses gosu correctly** |
| 5.5 | ✓ | Interactive may relax in task 2 |
| 6.1-6.6 | ✓ | Task 4 covers |
| 6.7 | ✗ | **References — task 4 adds to README but no verification** |
| 7.1-7.4 | ✓ | Task 5 covers |
| 7.5 | ✗ | **Sequential execution — not explicit in playbook structure** |

**Missing requirements needing tasks:**
- Req 1.3: Verify Dockerfile creates llama user with video/render groups
- Req 1.4: Install llama-server with LLAMA_CURL=ON and OPENSSL support
- Req 1.5: Set LD_LIBRARY_PATH, HF_HOME, PATH in Dockerfile
- Req 1.6: Install huggingface_hub and hf_transfer
- Req 3.5-3.6: Document 4-GPU tensor-split ratios (deferred to future work is acceptable with explicit note)
- Req 4.6: Verify stop-server.sh works
- Req 4.7: Document models.ini customization
- Req 5.3: Mount model directories read-only in run-server.sh
- Req 5.4: Verify gosu privilege drop in entrypoint.sh
- Req 7.5: Ensure playbook is sequentially executable

---

### 2. Design Consistency Issues

| Task | Issue |
|------|-------|
| Task 7 | **Contradicts design.md**: Design says "MTP requires --parallel 1. These are mutually exclusive." Task note is correct, but design.md also states `--parallel 3` for jukebox. This is inconsistent with MTP. The task correctly identifies the conflict but doesn't resolve it. |
| Task 8 | **Incomplete**: Design.md states the issue is CMD uses `--host 0.0.0.0` with `--network host`. Changing to `127.0.0.1` is correct, but design also mentions `--network host` is used. Binding to 127.0.0.1 with `--network host` works, but the task should note this combination. |
| Task 1 | **Missing flags**: Design.md mentions `GGML_HIP_ROCWMMA_FATTN=ON`. Task 1 mentions gfx targets but not this flag. Should verify it's in Dockerfile. |
| Task 9 | **Missing --parallel 1 for MTP**: Design.md shows MTP requires `--parallel 1`. If any model in models.ini uses MTP, this conflicts with multi-user serving. Task should note this constraint. |

---

### 3. Actionability Issues

| Task | Problem |
|------|---------|
| Task 3 | **Verification criteria incomplete**: "Manual test sequence" has 8 steps but no expected outputs. What does "confirm response" mean? What's the expected curl output? |
| Task 6 | **Checkpoint is vague**: "Ask user to verify on their hardware" is not actionable. Define what "pass" means. |
| Task 9 | **Missing expected outputs**: "container starts detached" — how to verify? What logs to check? What does successful swap look like? |
| Task 10 | **No specific tests**: "Add jukebox mode verification section" — what specific commands? What passes? |

---

### 4. Completeness Gaps

**Missing tasks for:**
1. **Dockerfile environment setup** (Req 1.5, 1.6): ENV directives for LD_LIBRARY_PATH, HF_HOME, PATH, and pip install of huggingface_hub/hf_transfer
2. **Dockerfile user creation** (Req 1.3): RUN useradd with video/render groups
3. **entrypoint.sh verification** (Req 5.4): Confirm gosu drops privileges correctly
4. **run-server.sh model directory mounts** (Req 5.3): Mount HF cache read-only
5. **stop-server.sh test** (Req 4.6): Verify it stops the container
6. **4-GPU documentation** (Req 3.5-3.6): This is correctly noted as future work, but should be explicit about what's out of scope

**Ambiguous ownership:**
- Who owns verification of existing entrypoint.sh? Not assigned.
- Who owns models.ini defaults? Task 5 mentions it but task 9 depends on it.

---

### 5. Technical Accuracy

| Issue | Location |
|-------|----------|
| Correct | gfx1201 target — ROCm 7.2.4 supports RDNA4 |
| Correct | b10106 commit pin — matches design |
| Correct | MTP flags (`--spec-type draft-mtp --spec-draft-n-max 2`) — matches design |
| Correct | Base image tag matches design |
| Missing | LLAMA_CURL=ON not mentioned in any task (Req 1.4) |
| Missing | OPENSSL support not mentioned (Req 1.4) |
| Ambiguous | Task 2 mentions `--tmpfs /tmp:rw,noexec,nosuid,size=256m` but design.md doesn't specify size. Is 256MB sufficient? For model cache? Design says `/tmp/.cache/llama.cpp` — this could grow large. |

---

### Remediation Actions

Insert these into TASKS.md ahead of current tasks:

1. **New Task 1a**: Verify Dockerfile user creation (Req 1.3)
   - File: Dockerfile
   - Verify: RUN useradd creates llama user with video,render groups

2. **New Task 1b**: Add environment variables and Python packages (Req 1.5, 1.6)
   - File: Dockerfile
   - Add: ENV LD_LIBRARY_PATH, HF_HOME, PATH
   - Add: pip install huggingface_hub hf_transfer

3. **New Task 1c**: Verify build flags (Req 1.1, design.md)
   - File: Dockerfile
   - Verify: GGML_HIP=ON, GGML_HIP_ROCWMMA_FATTN=ON, LLAMA_CURL=ON

4. **Update Task 3**: Add expected outputs to each verification step
   - Define what "confirm" means for each step

5. **New Task 5a**: Verify entrypoint.sh gosu usage (Req 5.4)
   - File: entrypoint.sh
   - Verify: exec gosu llama drops privileges

6. **Update Task 7**: Add read-only model mount
   - Add HF cache mount with :ro flag

7. **Update Task 9**: Add expected outputs and timing criteria
   - What does successful model swap look like in logs?
   - What's acceptable swap time (design says 3-10s)?

8. **New Task 9a**: Verify stop-server.sh (Req 4.6)
   - Verify container stops cleanly

9. **Update Task 10**: Add specific test commands
   - Exact curl commands, expected JSON responses

---

### Summary

- **PASS**: Core approach is sound, phase separation is correct
- **REVISE**: Missing 6 requirement traces, 4 actionability improvements needed, 2 design consistency issues to resolve
- **No REJECT issues**: Plan is fundamentally sound

## Notes

- Phase 1 is the immediate priority. Phase 2 builds on a working Phase 1.
- The Dockerfile change (task 1) is the only blocking change — everything else is script/docs.
- Current entrypoint.sh is adequate for both phases. No changes needed.
- models.ini tensor-split=9,16 is for the current 2-GPU config. Will need revisiting for 4-GPU.
- The kv-unified flag is proven working on the current system.
- The image name inconsistency (Dockerfile doesn't set a tag, scripts reference `rocm-llama-cpp:rocm724`) is resolved by the build command in README.
- 4-GPU tensor-split across 3 architectures is uncharted territory — interactive mode is essential for finding optimal splits.
- The R9700s haven't been physically installed yet. First milestone is getting the image to compile with gfx1201, then test once cards are in.
- Blog post at mywiredhouse.net documents the working 2-GPU journey and benchmarks.

## References

- [llama.cpp Discussion #21043 — RDNA4 Optimization](https://github.com/ggml-org/llama.cpp/discussions/21043): Comprehensive R9700 benchmarking with Vulkan
- [Phoronix: ROCm 7.1 vs RADV Vulkan on R9700](https://www.phoronix.com/review/rocm-71-llama-cpp-vulkan/2): Vulkan outperforms HIP on RDNA4
- [llama.cpp build docs — HIP section](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md): Official build instructions with GPU_TARGETS
- [ROCm 7.2.0 release notes](https://rocm.docs.amd.com/en/docs-7.2.0/about/release-notes.html): RDNA4 support added
- [unsloth/Qwen3.6-27B-MTP-GGUF](https://huggingface.co/unsloth/Qwen3.6-27B-MTP-GGUF): MTP-enabled model for ~2x decode speedup
