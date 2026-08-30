# Dual R9700 AITER and MTP experiment plan

## Objective

Determine whether AITER can provide a usable and faster flash-attention path for the two Radeon AI PRO R9700 GPUs, then test native MTP separately. Do not change the working ROCm container or commit speculative work. A change is commit-worthy only if it is reproducible, improves a controlled benchmark, and does not regress model loading or API behavior.

The primary hardware is the validated dual-R9700 setup:

- ROCm device 0 and device 3: AMD Radeon AI PRO R9700, `gfx1201`.
- Selection: `HIP_VISIBLE_DEVICES=0,3`.
- Image: `rocm-llama-cpp:rocm714`.
- llama.cpp: `9723942adc518b43c4b95dc4dce6906903eb5e09`.
- Existing HIP build flag: `GGML_HIP_ROCWMMA_FATTN=ON`.
- Primary model: `unsloth/Qwen3.8-27B-GGUF`, using the cached GGUF and the same quantization for every comparison.

## Evidence and working assumptions

The user-provided captures under `research/rocm_info/` make the supplied Reddit threads independently readable. They are still community reports, so their performance numbers are hypotheses to reproduce rather than guaranteed results:

- [r/ROCm: 2x R9700 running Qwen3.6 27B with AITER unified](https://www.reddit.com/r/ROCm/comments/1tmr2j8/2x_r9700_running_qwen36_27b_with_aiter_unified/)
- [r/LocalLLaMA: 2 Radeon R9700 for local AI](https://www.reddit.com/r/LocalLLaMA/comments/1vamrls/2_radeon_r9700_for_local_ai_was_choosing_amd/)

The important distinction is that the first thread uses **vLLM**, not llama.cpp. Its reported AITER path is a patched vLLM ROCm-wheel image, with the patch [GFX12x_R9700_RUNTIME.patch](https://github.com/andysalerno/r9700-serving/blob/main/docker/patches/GFX12x_R9700_RUNTIME.patch). The capture reports:

- ROCm 7.13 and a nightly vLLM wheel profile.
- `VLLM_ROCM_USE_AITER=1` and `VLLM_ROCM_USE_AITER_UNIFIED_ATTENTION=1`.
- Other AITER paths disabled: MHA, MLA, MOE, linear, FP8 BMM, FP4 BMM, Triton GEMM, and RMSNorm.
- `VLLM_ROCM_SHUFFLE_KV_CACHE_LAYOUT=0`.
- `MTP=3`, `GPU_MAX_HW_QUEUES=1`, and community comments recommending `NCCL_PROTO=Simple` and `--max-num-seqs 4` for stability/performance.
- A reported Qwen3.6-27B-FP8 generation rate around 69--78 tok/s through 64k depth, versus roughly 7 tok/s for the author's unpatched vLLM configuration. These are vLLM results, not llama.cpp results, and are not a direct AITER-vs-ROCWMMA comparison.
- The capture also records cold starts of up to 15 minutes and reports from users who still could not start the stack, so reproducibility is a required gate.

The second thread supplies llama.cpp-specific hypotheses:

- On an R9700, F16 KV cache may outperform Q8 KV cache at long context because the attention path avoids KV dequantization; the captured data reports the advantage growing with prompt length, but it used Vulkan, not ROCm HIP.
- The captured llama.cpp command used `--flash-attn on`, `--ctx-size 262144`, `--spec-type draft-mtp`, and `--spec-draft-n-max 3`, with separate F16 and Q8 KV-cache arms.
- The thread also points to an AITER-enabled vLLM fork, reinforcing that AITER and llama.cpp's native attention path are separate experiments.

Current GitHub evidence supplies the safety boundaries:

- [ROCm/aiter issue #3294](https://github.com/ROCm/aiter/issues/3294) says `gfx1201`/R9700 support is still work in progress: Triton is the first functional path, while HIP/flyDSL kernels are being developed for performant support.
- [ROCm/aiter issue #1436](https://github.com/ROCm/aiter/issues/1436) describes allowing experimentation on architectures that AITER does not yet support. An architecture override is not evidence of native support.
- Current llama.cpp search found no native `GGML_HIP_AITER` integration. Its HIP flash-attention implementation is the ROCWMMA path, enabled here with `GGML_HIP_ROCWMMA_FATTN=ON` and selected at runtime by `--flash-attn on`.
- Current llama.cpp supports `--split-mode tensor`, `--tensor-split`, quantized KV-cache options, and native MTP through `--spec-type draft-mtp`.
- Current MTP reports show context-size and VRAM tradeoffs, acceptance-rate sensitivity, and possible instability with tensor mode. MTP must therefore be tested after the attention experiment and with `--parallel 1`.
- A Qwen3.8 MTP GGUF is not assumed to exist in the cached Unsloth repository. MTP testing first requires locating a compatible GGUF with native MTP tensors or an explicitly compatible draft model, then validating its metadata and license/source.

## Execution sequence

### 1. Establish the ROCWMMA baseline

Use the same container, model, device selection, tensor split, batch parameters, and repetitions for all baseline runs. Record:

- Full image ID and llama.cpp commit.
- ROCm device list, driver/kernel information, and `HIP_VISIBLE_DEVICES=0,3`.
- Model path, file size, and quantization.
- `llama-bench` command, stdout/stderr, and date.
- Prompt throughput, generation throughput, load time, and any warnings.
- VRAM usage if available from the host GPU monitor.

Baseline matrix:

- `--flash-attn off`: control.
- `--flash-attn on`: current ROCWMMA flash-attention path.
- Optional separate KV-cache controls: `--cache-type-k q8_0 --cache-type-v q8_0`, but never mix this result into the primary FA on/off comparison.

Recommended benchmark shape:

```bash
llama-bench \
  --hf-repo unsloth/Qwen3.8-27B-GGUF \
  --offline \
  --split-mode tensor \
  --tensor-split 1,1 \
  -ngl all \
  -p 128,512,2048,8192 \
  -n 128 \
  -b 4096 \
  -ub 1024 \
  -r 3 \
  -fa on
```

Run the same command with `-fa off`. If the full long-prompt matrix cannot fit or complete, retain the shorter completed rows and record the failure rather than changing parameters silently. The benchmark is executed inside the launcher with `HIP_VISIBLE_DEVICES=0,3`; it must not use the host's unrestricted device list.

### 2. AITER feasibility gate for llama.cpp only

The pasted Reddit AITER recipe targets patched vLLM, not llama.cpp. It is retained as context for the R9700 architecture, but vLLM is out of scope for this experiment. No vLLM image, benchmark, patch, or environment will be introduced.

Before changing the llama.cpp Dockerfile:

1. Inspect the pinned llama.cpp source/build metadata for any native AITER backend, CMake option, or HIP attention call site. The initial search found no `GGML_HIP_AITER` integration.
2. Check whether the runtime contains an AITER package or importable module. A Python package alone does not make it usable by llama.cpp's C++ HIP backend.
3. Check AITER's current architecture list and documented C++/HIP integration API for `gfx1201`.
4. If a documented llama.cpp integration point exists, attempt only a minimal disposable build or standalone kernel probe. Do not change the working image tag.
5. Record exact errors, architecture overrides, and whether an AITER kernel actually ran through llama.cpp on both R9700s.

Decision gates:

- **FAIL:** no llama.cpp integration exists, AITER rejects `gfx1201`, or only an unsupported architecture override works. Stop implementation and conclude that the current llama.cpp ROCWMMA path is the supported option.
- **PARTIAL:** a standalone AITER experiment runs outside llama.cpp but cannot be connected to llama.cpp without an undocumented or large custom port. Record it as non-actionable evidence and do not claim AITER flash attention in llama.cpp.
- **PASS:** a documented AITER C++/HIP integration exists for `gfx1201`, builds in a throwaway llama.cpp image, serves the same model, and passes deterministic output checks. Only then compare it with the native ROCWMMA build.

No AITER package, architecture override, or custom integration is added to the production image before the gate passes.

### 3. AITER comparison, only if llama.cpp integration is feasible

If the llama.cpp gate reaches PASS, keep `rocm-llama-cpp:rocm714` unchanged and use a separate tagged image. Rerun the exact llama-bench matrix used for the native baseline. Compare prompt throughput, generation throughput, model load time, VRAM, stability, and deterministic output. AITER is considered beneficial only if the same llama.cpp workload shows a reproducible improvement across repeated runs with no regression. If the gate fails or the result is neutral, discard the disposable image and do not commit an AITER integration.

### 4. MTP investigation after the AITER decision

MTP is an independent experiment. First locate a compatible Qwen MTP GGUF. Do not use `unsloth/Qwen3.8-27B-GGUF` as an MTP model unless its metadata confirms native MTP tensors.

For a compatible model, compare native generation against:

```bash
--spec-type draft-mtp --spec-draft-n-max 2
```

Then test `--spec-draft-n-max 3` only if the first setting is stable. Keep `--parallel 1`, use the same prompt, context, batch sizes, KV-cache types, and tensor split, and record acceptance statistics, generation throughput, VRAM, output correctness, and crashes. Start with a safe context smaller than the 256k production target; increase only after the short test is stable.

Because community reports describe dual-R9700 tensor-mode MTP crashes, stop immediately on a GPU hang, driver reset, or hardware-level failure. MTP is not a reason to alter the stable image without a separate reproducible result.

## Documentation and commit gates

`r9700_performance.md` will contain raw commands and results, not only conclusions. It will separate:

1. current ROCWMMA baseline;
2. AITER feasibility and any standalone result;
3. AITER integrated comparison, if one exists;
4. MTP prerequisites and results;
5. final recommendation and known limitations.

Commit policy:

- Always preserve the working image tag and clean up disposable images.
- Commit documentation when the experiment is complete if requested work is captured cleanly.
- Commit Dockerfile or source integration only when AITER has a reproducible, measured benefit and the final image passes the existing smoke tests.
- Do not commit an architecture override, failed experiment, unverified Reddit recipe, or an AITER package that does not support `gfx1201`.

Rollback is deleting the disposable experiment image and reverting the isolated working-tree changes. The stable `rocm-llama-cpp:rocm714` image remains the control throughout.
