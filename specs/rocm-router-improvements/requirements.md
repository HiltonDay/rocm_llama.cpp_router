# Requirements Document

## Introduction

Docker-based multi-model inference server using llama.cpp on AMD GPUs via ROCm HIP. The system runs on mixed-architecture multi-GPU setups and must compile for all GPU architectures present in the system.

The project has two phases:
1. **Interactive Docker** — a working, debuggable container with GPU access where llama-server can be manually run, benchmarked, and tuned
2. **Jukebox Mode** — automated router mode with models-preset for multi-model swap

Phase 1 must be fully proven before Phase 2 begins.

## Hardware Context

### Target System (4 GPUs, 3 architectures)
- GPU: AMD Instinct MI100 (gfx908, CDNA, 32GB)
- GPU: AMD Radeon RX 7900 XTX (gfx1100, RDNA3, 24GB) — also drives display output
- GPU: AMD Radeon AI PRO R9700 #1 (gfx1201, RDNA4, 32GB)
- GPU: AMD Radeon AI PRO R9700 #2 (gfx1201, RDNA4, 32GB)
- Total VRAM: ~120GB across 3 architectures (gfx908, gfx1100, gfx1201)
- Host: Fedora 44, ROCm 7.2.2
- Base image: `rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0`
- Build targets: `LLAMACPP_ROCM_ARCH="gfx908,gfx1100,gfx1201"`

### Current Working Config (2 GPUs, R9700s not yet installed)
- 7900 XTX (24GB, needs ~2GB for display) + MI100 (32GB)
- Useable VRAM: ~52GB
- Tensor-split: 5/8 or 9/16 (protects display GPU from OOM)
- 256k context achieved with Qwen3.6-35B-A3B MoE Q8_0

### R9700 Notes (gfx1201, RDNA4)
- ROCm 7.2+ supports RDNA4 natively
- Vulkan/RADV currently faster than HIP on RDNA4 for llama.cpp decode (Phoronix, Discussion #21043)
- HIP build works and is improving with each ROCm release
- MTP (multi-token prediction) provides ~2x decode speedup on supported models
- PCIe ASPM=performance gives +10.8% dense decode
- Key bench flags: `-b 16384 -ub 2048 -fa 1`

### Proven Performance (current system, HIP, FA on, Q8_0, dual-GPU)

| Model | PP2048 | TG128 | Notes |
|-------|--------|-------|-------|
| Qwen3.6-27B Q8_0 | 1172 t/s | 23.49 t/s | Dense, 26.62 GiB |
| Qwen3.6-27B Q8_0 (ts 5/8) | 1102 t/s | 23.48 t/s | With tensor-split |
| Qwen3.6-35B-A3B MoE Q8_0 | 1930 t/s | 62.12 t/s | MoE, 34.36 GiB |
| gemma-4-31B-it Q8_0 | 857 t/s | 21.10 t/s | Dense, 30.38 GiB |
| gemma-4-26B-A4B-it Q8_0 | 2280 t/s | 60.94 t/s | MoE, 25.00 GiB |
| Llama-3.3-70B Q4_0 | 443 t/s | 17.37 t/s | Dense, 37.35 GiB |

### Backend Decision: HIP

The Docker image builds with GGML_HIP=ON because:
- The base image (`rocm/pytorch`) provides the full HIP toolchain
- HIP enables unified KV cache (`--kv-unified`), flash attention via rocWMMA
- Multi-architecture builds (gfx908 + gfx1100 + gfx1201) work naturally
- The current system already achieves good performance with HIP
- For RDNA4 (gfx1201) specifically, Vulkan/RADV may be faster — users wanting maximum R9700 throughput should also try a native Vulkan build on the host

## Glossary

- **Container**: The Docker container running the llama.cpp server image
- **Image**: The Docker image built from the Dockerfile
- **Host**: The physical machine running Fedora 44 with AMD GPUs and ROCm 7.2.2
- **llama-server**: The llama.cpp HTTP inference server binary compiled with HIP
- **Jukebox Mode**: llama-server operating as a model dispatcher using --models-preset (swap models on demand)
- **ROCm**: AMD's open-source GPU compute platform (7.2.2 on host, 7.2.4 in container)
- **HIP**: AMD's GPU programming interface (analogous to CUDA)
- **gfx908**: GPU architecture for MI100 (CDNA, Wave Size 64)
- **gfx1100**: GPU architecture for 7900 XTX (RDNA3, Wave Size 32)
- **gfx1201**: GPU architecture for R9700 (RDNA4, Wave Size 32) — planned addition
- **GPU_Devices**: /dev/kfd and /dev/dri device nodes required for ROCm GPU access
- **HF_Cache**: HuggingFace model cache directory on the host (~/.cache/huggingface/)
- **Models_INI**: INI configuration file defining per-model settings for jukebox mode
- **tensor-split**: Ratio controlling how model layers are distributed across GPUs (e.g., 5/8 or 9/16)
- **kv-unified**: Flag enabling unified KV cache across GPU devices
- **MTP**: Multi-Token Prediction — speculative decoding using model's built-in prediction heads (~2x on R9700)

## Requirements

### Requirement 1: Docker Image Build with gfx1201 Support

**User Story:** As a developer with R9700 GPUs, I want to build the Docker image targeting gfx1201 (RDNA4) so that llama-server uses my GPU architecture natively.

#### Acceptance Criteria

1. WHEN the Dockerfile is built, THE Image SHALL compile llama-server with GGML_HIP=ON and GGML_HIP_ROCWMMA_FATTN=ON targeting gfx1201 (primary), with gfx908 and gfx1100 as additional targets
2. WHEN the Dockerfile is built, THE Image SHALL use a ROCm 7.2.4+ base image that includes RDNA4 support
3. WHEN the Dockerfile is built, THE Image SHALL create a non-root user (llama) with membership in the video and render groups
4. WHEN the Dockerfile is built, THE Image SHALL install llama-server and llama-bench binaries with all required shared libraries
5. WHEN the Dockerfile is built, THE Image SHALL set LD_LIBRARY_PATH, HF_HOME, and PATH appropriately
6. WHEN the Dockerfile is built, THE Image SHALL include huggingface_hub and hf_transfer for model management
7. WHEN the Dockerfile is built, THE Image SHALL track llama.cpp master (latest commit at build time) unless a specific commit is pinned for stability

### Requirement 2: Interactive Docker (Phase 1)

**User Story:** As a developer, I want to log into the container with full GPU access and all environment variables set, so that I can manually start llama-server, run llama-bench, and debug the environment.

#### Acceptance Criteria

1. WHEN the interactive script launches the Container, THE Container SHALL start with a bash shell with GPU access available
2. WHILE the Container is running, THE Container SHALL have /dev/kfd and /dev/dri accessible with correct group permissions
3. WHILE the Container is running, THE Container SHALL have HF_Cache mounted (read-write) so models are accessible
4. WHILE the Container is running, THE llama user SHALL have confirmed membership in video and render groups (verifiable via `id` command)
5. WHILE the Container is running, THE Container SHALL have llama-server and llama-bench on PATH and functional
6. WHEN the user manually invokes llama-server with a model, THE server SHALL detect and use the R9700 GPU(s)
7. WHEN the user runs llama-bench, THE benchmark SHALL execute against the GPU and report results
8. WHILE the Container is running, THE Container SHALL support both single-GPU and dual-GPU configurations via HIP_VISIBLE_DEVICES or tensor-split flags
9. THE interactive container SHALL allow the user to test PCIe ASPM settings, MTP flags, and batch tuning parameters documented in the performance notes

### Requirement 3: Dual-GPU Configuration

**User Story:** As a developer with two R9700 GPUs, I want the container to support multi-GPU inference so that I can use both cards for larger models or faster prefill.

#### Acceptance Criteria

1. WHEN both GPUs are passed to the Container, THE llama-server SHALL detect both devices
2. WHEN tensor-split is configured, THE llama-server SHALL distribute model layers across GPUs according to the specified ratio
3. THE models.ini SHALL include tensor-split configuration appropriate for dual R9700 (equal split: 0.5/0.5 or memory-based)
4. THE documentation SHALL note that dual-GPU decode is slower than single-GPU for bandwidth-bound models, and describe when dual-GPU is beneficial (long-context prefill, larger models that don't fit in 32GB)

### Requirement 4: Jukebox Mode (Phase 2 — Router)

**User Story:** As a developer, I want llama-server to run in router mode with models-preset, supporting dynamic model loading and unloading, so that chat interfaces can switch between models automatically.

#### Acceptance Criteria

1. WHEN the Container starts in Jukebox mode, THE llama-server SHALL start using --models-preset pointing to Models_INI with --models-max 1
2. WHEN a client requests a model not currently loaded, THE llama-server SHALL unload the current model and load the requested one
3. WHEN the Container starts, THE llama-server SHALL respond to GET /v1/models with all models defined in Models_INI
4. WHEN a model swap occurs, THE swap SHALL complete within expected timeframe (3-10 seconds depending on model size)
5. THE Container SHALL maintain security hardening: read-only filesystem, tmpfs at /tmp, no-new-privileges, localhost binding
6. THE Container SHALL be manageable via start/stop scripts
7. THE models.ini SHALL be configurable for the user's specific models and GPU memory constraints

### Requirement 5: Security Hardening

**User Story:** As a developer, I want the container to follow defense-in-depth principles with minimal attack surface.

#### Acceptance Criteria

1. WHEN run-server.sh launches the Container, THE script SHALL use --read-only, tmpfs at /tmp, --security-opt no-new-privileges
2. WHEN run-server.sh launches the Container, THE script SHALL bind llama-server to 127.0.0.1 (localhost only) unless explicitly overridden
3. WHEN run-server.sh launches the Container, THE script SHALL mount model directories read-only where possible
4. THE entrypoint SHALL drop privileges appropriately when running llama-server
5. THE interactive container MAY relax read-only filesystem for debugging convenience (tmpfs still applies)

### Requirement 6: Performance Tuning Documentation

**User Story:** As a developer, I want documented performance tuning guidance for R9700 GPUs so that I can get maximum throughput from my hardware.

#### Acceptance Criteria

1. THE documentation SHALL include PCIe ASPM performance mode instructions and expected gains
2. THE documentation SHALL include optimal llama-bench flags for R9700 (-b 16384 -ub 2048 -fa 1)
3. THE documentation SHALL note that Vulkan/RADV currently outperforms HIP on RDNA4 with links to benchmarks
4. THE documentation SHALL include MTP (multi-token prediction) usage for supported models
5. THE documentation SHALL include dual-GPU tensor-split recommendations and the decode vs prefill tradeoff
6. THE documentation SHALL reference the llama.cpp Discussion #21043 and community optimization findings

### Requirement 7: Test Verification

**User Story:** As a developer, I want documented verification steps so that I can confirm the system works without AI assistance.

#### Acceptance Criteria

1. THE project SHALL include a TEST_PLAYBOOK.md with pre-flight checks and verification commands
2. THE playbook SHALL cover: GPU detection, environment variables, model loading, HTTP API, benchmarking
3. THE playbook SHALL include troubleshooting for common failures (GPU permissions, library paths, model not found, OOM)
4. THE playbook SHALL be executable by following commands sequentially without external knowledge
