# Design Document: ROCm Docker for R9700 (gfx1201)

## Overview

Docker-based llama.cpp inference server targeting a 4-GPU mixed-architecture system:
- AMD Instinct MI100 (gfx908, CDNA, 32GB)
- AMD Radeon RX 7900 XTX (gfx1100, RDNA3, 24GB)
- 2x AMD Radeon AI PRO R9700 (gfx1201, RDNA4, 32GB each)

Total: ~120GB VRAM, 3 architectures. Two phases:

1. **Interactive Docker** — working container with GPU access for manual server operation, benchmarking, and tuning
2. **Jukebox Mode** — automated router mode with models-preset

The existing codebase has a working Dockerfile, entrypoint, and scripts proven on the 2-GPU config (MI100 + 7900 XTX). Changes needed:
- Add gfx1201 to AMDGPU_TARGETS
- Verify 4-GPU detection and tensor-split across 3 architectures
- Restructure scripts to support interactive-first workflow
- Add performance tuning documentation
- Prepare jukebox mode (router) as Phase 2

### Key Design Decisions

1. **HIP build, not Vulkan**: The Docker image builds with GGML_HIP=ON because the ROCm base image provides the full HIP toolchain. Vulkan (RADV) is currently faster on RDNA4 for llama.cpp decode, but requires host-side Mesa/RADV drivers rather than container-side support. Users wanting Vulkan should build llama.cpp natively on the host. The HIP path provides a self-contained Docker experience.

2. **gfx1201 as additional target**: Build targets `gfx908,gfx1100,gfx1201` to cover all cards. More targets = longer compile. Users can trim to their hardware.

3. **Interactive-first**: The default launch is an interactive shell, not a detached server. This matches the development workflow: verify GPU access → run benchmarks → tune parameters → only then automate.

4. **gosu for privilege management**: Current entrypoint uses gosu, which is simpler than setpriv for the container use case. Keep it.

5. **Dual-GPU aware but not dual-GPU default**: Models.ini includes tensor-split for multi-GPU. Interactive mode lets users experiment with different splits manually — especially important with 4 GPUs across 3 architectures where optimal split isn't obvious.

## Architecture

### File Structure

```
rocm_docker/
├── Dockerfile              # Build image with HIP for gfx1201, gfx908, gfx1100
├── entrypoint.sh           # Privilege drop, XDG/cache setup, exec
├── run-server.sh           # Detached jukebox mode (Phase 2)
├── interactive-server.sh   # Interactive shell with GPU access (Phase 1)
├── stop-server.sh          # Stop the detached server
├── models.ini              # Router mode model configuration
├── TEST_PLAYBOOK.md        # Verification procedures
├── README.md               # Project overview + performance tuning
├── .dockerignore           # Build context exclusions
└── LICENSE                 # License
```

### Phase 1: Interactive Docker Flow

```
User runs ./interactive-server.sh
  → docker run -it with GPU devices, HF cache mount
  → entrypoint.sh sets up cache dirs, drops to llama user
  → User gets bash shell inside container
  → User manually runs: llama-server, llama-bench, environment checks
  → User tunes parameters, tests models
  → User exits (container removed due to --rm)
```

### Phase 2: Jukebox Mode Flow

```
User runs ./run-server.sh
  → docker run -d with GPU devices, HF cache mount, security hardening
  → entrypoint.sh sets up cache, execs llama-server with router args
  → llama-server starts in --models-preset mode
  → Serves OpenAI-compatible API on localhost:8000
  → Models swap on demand (--models-max 1)
User runs ./stop-server.sh to terminate
```

### Container Architecture

```
Host                              Container
─────                             ─────────
/dev/kfd, /dev/dri   ──────────→  GPU access (--device)
~/.cache/huggingface ──────────→  /tmp/huggingface (bind mount, rw)
                                  
                                  /usr/local/bin/llama/
                                    ├── llama-server
                                    ├── llama-bench
                                    └── *.so (shared libs)
                                  
                                  /etc/llama-server/models.ini
                                  
                                  User: llama (video, render groups)
                                  Cache: /tmp/.cache/llama.cpp
```

## Components

### Component 1: Dockerfile

**Current state**: Working build targeting gfx908, gfx1100 on ROCm 7.2.4 base image.

**Changes needed**:
- Add `gfx1201` to LLAMACPP_ROCM_ARCH
- Keep GGML_HIP_ROCWMMA_FATTN=ON (benefits RDNA3+ and CDNA)
- Keep current binary layout (/usr/local/bin/llama/)
- Keep current user setup (llama with video, render groups)

```dockerfile
ENV LLAMACPP_ROCM_ARCH="gfx908,gfx1100,gfx1201"
```

The CMD remains the jukebox mode command. The interactive script overrides via --entrypoint.

### Component 2: interactive-server.sh

**Current state**: Working — launches bash with --entrypoint /bin/bash override.

**Changes needed**:
- Already functional as-is
- Consider adding `--read-only` with `--tmpfs /tmp` for consistency with production
- May keep without --read-only for debugging convenience (write to /tmp is sufficient)
- Current form is fine for Phase 1

### Component 3: run-server.sh (Phase 2)

**Current state**: Detached launch with read-only filesystem and security hardening.

**Changes needed**:
- Update image name to match build tag
- Add documentation about security flags
- Ensure it passes GPU devices correctly for dual-GPU
- Bind to 127.0.0.1 (currently uses --network host, server CMD has --host 0.0.0.0)

**Issue**: Current CMD uses `--host 0.0.0.0` which exposes on all interfaces. With `--network host` this means the server is accessible from the network. Should be changed to `127.0.0.1` for localhost-only access.

### Component 4: entrypoint.sh

**Current state**: Minimal — creates cache dir, chowns, execs gosu llama with passed command.

**Adequate for both phases**. Interactive mode passes `/bin/bash`, jukebox mode passes the llama-server command via CMD.

### Component 5: models.ini

**Current state**: Configured for 4 models with tensor-split=9,16 and kv-unified=true.

**Changes needed**:
- Document what tensor-split=9,16 means (split ratio across two GPUs)
- Consider whether kv-unified=true is appropriate for gfx1201 (it's a newer feature)
- Values look correct for dual R9700 setup

### Component 6: TEST_PLAYBOOK.md

**Current state**: Exists but may need updating.

**Content needed**:
- Pre-flight: GPU detection, driver version, model availability
- Phase 1 verification: interactive shell checks
- Phase 2 verification: jukebox mode API tests
- Performance tuning checklist
- Troubleshooting

## Performance Tuning Notes (for documentation)

### Current System Performance (MI100 + 7900 XTX, HIP, FA on)

Proven benchmarks from the working 2-GPU setup:
- Qwen3.6-35B-A3B MoE Q8_0: 1930 t/s pp, 62 t/s tg — excellent for MoE
- Qwen3.6-27B Q8_0 (ts 5/8): 1102 t/s pp, 23.5 t/s tg — dense, bandwidth-bound
- 256k context with `--parallel 3 --kv-unified -ts 5/8`

### R9700 (gfx1201) — Community Benchmarks (Vulkan/RADV)

From llama.cpp Discussion #21043:
- Qwen3.5-27B Q4_K_M: ~29 t/s decode (RADV stock), ~32.5 t/s with ASPM fix
- Qwen3.5-35B-A3B MoE Q4_K_XL: ~148-156 t/s decode, 3074 t/s pp2048 with -ub 2048
- MTP on Qwen3.6-27B: 44-48 t/s (from ~20 t/s base) — ~2x boost

### 4-GPU Considerations

When all 4 cards are installed:
- Tensor-split ratio needs benchmarking (3 different memory bandwidths, 3 architectures)
- The 7900 XTX still needs display reservation (~2GB)
- PCIe topology will determine inter-GPU communication overhead
- May benefit from running separate instances per GPU pair rather than one 4-GPU split
- Llama.cpp multi-GPU uses layer-wise splitting — uneven architectures means the slowest GPU is the bottleneck for TG

### Host-Side Optimizations (not container-managed)

```bash
# PCIe ASPM — +10.8% dense decode on RADV, may help HIP too
echo "performance" | sudo tee /sys/module/pcie_aspm/parameters/policy

# GPU performance mode — stable clocks
echo high | sudo tee /sys/class/drm/card*/device/power_dpm_force_performance_level
```

### llama-bench Recommended Flags

```bash
llama-bench -m MODEL.gguf -t 1 -ngl 99 -fa 1 \
  -p 128,512,2048,8192 -n 128,512,2048 \
  -b 16384 -ub 2048 -r 3
```

### MTP (Multi-Token Prediction)

For models with MTP support (e.g., `unsloth/Qwen3.6-27B-MTP-GGUF`):
```bash
llama-server --model hf=unsloth/Qwen3.6-27B-MTP-GGUF:Q4_K_M \
  --draft-n-max 3 --draft-min 1
```
Expected: ~2x decode speedup with 85-95% acceptance rate.

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| `/dev/kfd: Permission denied` | Missing --device or user not in video group | Check --device and --group-add flags |
| `hipErrorNoBinaryForGpu` | Binary not compiled for this GPU arch | Verify gfx1201 in LLAMACPP_ROCM_ARCH, rebuild |
| `cannot open shared object file` | LD_LIBRARY_PATH wrong | Check /usr/local/bin/llama/ has .so files |
| Model not found | HF cache not mounted or wrong path | Verify -v mount and HF_HOME env var |
| OOM / VRAM exhausted | Model + KV cache exceeds 32GB | Reduce --ctx-size, use lower quant, or enable dual-GPU split |
| Port already in use | Another process on 8000 | `lsof -i :8000` on host |

## Testing Strategy

Manual verification via TEST_PLAYBOOK.md. No automated tests — the system requires real GPU hardware. The playbook provides exact commands with expected outputs for:

1. GPU detection and architecture confirmation
2. Environment and permission verification
3. Model loading and inference
4. Benchmark execution
5. API endpoint testing (Phase 2)
