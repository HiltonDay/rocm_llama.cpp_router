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
