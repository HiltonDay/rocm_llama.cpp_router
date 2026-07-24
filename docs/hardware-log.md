# Hardware Configuration Log

## Current System

- **Host OS**: Fedora 44, ROCm 7.2.2 (EL10 build from ROCm repo)
- **CPU**: Not specified (sufficient for multi-GPU)
- **RAM**: Not specified

## GPUs

| Slot | GPU | Architecture | VRAM | Wave Size | Notes |
|------|-----|-------------|------|-----------|-------|
| 0 | AMD Instinct MI100 | gfx908 (CDNA) | 32 GB | 64 | Power limited to 200W for thermals |
| 1 | AMD Radeon RX 7900 XTX | gfx1100 (RDNA3) | 24 GB | 32 | Also drives display, ~2GB reserved |
| TBD | AMD Radeon AI PRO R9700 #1 | gfx1201 (RDNA4) | 32 GB | 32 | Not yet installed |
| TBD | AMD Radeon AI PRO R9700 #2 | gfx1201 (RDNA4) | 32 GB | 32 | Not yet installed |

**Total VRAM (all 4 installed):** 120 GB across 3 architectures

### Current Working Config (2 GPUs)
- Useable VRAM: ~52 GB (24 - 2 display + 32 = 54, practical ~52)
- Tensor-split: `5/8` (blog) or `9/16` (models.ini) — protects display GPU
- 256k context achieved with Qwen3.6-35B-A3B MoE Q8_0

### Planned Config (4 GPUs)
- Useable VRAM: ~118 GB
- Three architectures require `LLAMACPP_ROCM_ARCH="gfx908,gfx1100,gfx1201"`
- Tensor-split will need recalculating for 4-way split
- PCIe topology matters — need to check available lanes/slots

## Benchmark Baselines (2-GPU, HIP, FA on, Q8_0)

| Model | Size | PP2048 | TG128 | tensor-split |
|-------|------|--------|-------|--------------|
| Qwen3.6-27B Q8_0 | 26.62 GiB | 1172 t/s | 23.49 t/s | default |
| Qwen3.6-27B Q8_0 | 26.62 GiB | 1102 t/s | 23.48 t/s | 5/8 |
| Qwen3.6-35B-A3B MoE Q8_0 | 34.36 GiB | 1930 t/s | 62.12 t/s | default |
| gemma-4-31B-it Q8_0 | 30.38 GiB | 857 t/s | 21.10 t/s | default |
| gemma-4-26B-A4B-it Q8_0 | 25.00 GiB | 2280 t/s | 60.94 t/s | default |
| Llama-3.3-70B Q4_0 | 37.35 GiB | 443 t/s | 17.37 t/s | default |

Source: https://mywiredhouse.net/blog/rocm-with-two-different-gpus-how-hard-can-it-be/

## R9700 Community Benchmarks (single GPU, Vulkan/RADV)

From llama.cpp Discussion #21043:

| Model | Backend | TG128 | PP2048 | Notes |
|-------|---------|-------|--------|-------|
| Qwen3.5-27B Q4_K_M | RADV | 29.07 t/s | 799 t/s | Stock |
| Qwen3.5-27B Q4_K_M | RADV+ASPM | 32.46 t/s | — | +10.8% from ASPM=performance |
| Qwen3.5-35B-A3B MoE Q4_K_XL | RADV | 147.8 t/s | 2,381 t/s | Stock |
| Qwen3.5-35B-A3B MoE Q4_K_XL | RADV+ub2048 | 147.9 t/s | 3,074 t/s | +29% prefill |
| Qwen3.6-27B Q4_K (MTP) | RADV | 44-48 t/s | ~470-560 t/s | MTP ~2x boost |

Key: Vulkan/RADV currently outperforms HIP on RDNA4 for decode. HIP performance improving.

## Key Technical Findings

### MTP (Multi-Token Prediction)
- Merged into llama.cpp mainline via PR #22673 (May 16, 2026, build b9235)
- Requires MTP-specific GGUF files (e.g., `unsloth/Qwen3.6-27B-MTP-GGUF`)
- Flags: `--spec-type draft-mtp --spec-draft-n-max 2` (or 3)
- **Limitation: requires --parallel 1** — cannot be used with multi-slot serving
- Expected speedup: ~1.5-2x decode with 80-95% acceptance rate

### Multi-GPU (split-mode layer)
- Default and most compatible mode for mixed architectures
- Tensor-split ratio set with `-ts` (e.g., `5/8` for uneven VRAM)
- `--split-mode tensor` is experimental, NOT supported for MoE, requires f16/bf16 KV cache
- RCCL disabled by default in llama.cpp ROCm ("not universally beneficial")
- Dual-GPU decode is slower than single for bandwidth-bound models (15-26% penalty)
- Dual-GPU prefill gains 35-80% at long contexts (pp8192+)

### llama.cpp Version
- Current Dockerfile pinned to: b10106 (latest stable release)
- Includes: MTP, multi-GPU layer split, flash attention rocWMMA, gfx1201 HIP support
- Base image: rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0 (stable legacy stream)
- ROCm 7.14 (TheRock) exists but is new/preview — staying on 7.2.4 for stability
