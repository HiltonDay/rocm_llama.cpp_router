# Dual R9700 performance results

Date: 2026-08-31

## Conclusion

The current llama.cpp ROCm image does not have a usable AITER integration. The production image contains no `aiter` Python module, the llama-server binary contains no AITER symbols, and the pinned llama.cpp tree exposes the native HIP ROCWMMA flash-attention path rather than an AITER backend. Current ROCm/aiter issue #3294 also describes `gfx1201` support as work in progress. No AITER Dockerfile or source change was made and no AITER improvement can be committed for this llama.cpp-only project.

Native llama.cpp MTP does work with the cached Qwen3.8-27B GGUF. The model contains embedded `nextn` tensors. At a safe 4096-token context, dual-R9700 tensor mode increased measured API generation throughput from about 28.8 tok/s to 55.8 tok/s with draft depth 2, and to 60.4 tok/s with draft depth 3. Draft depth 3 had lower acceptance than depth 2 in this short test, but still produced the highest throughput. A separate 262,144-token startup smoke test with Q8 KV caches loaded the model and served one short request, accepting 10 of 14 draft tokens. The requested FP16-KV variant also loaded at 262,144 tokens and served a short request, accepting 11 of 12 draft tokens. Neither 256k smoke test was a repeated long-context throughput benchmark.

## Hardware and software

- GPUs: two AMD Radeon AI PRO R9700, `gfx1201`.
- ROCm selection: `HIP_VISIBLE_DEVICES=0,3`.
- Image: `rocm-llama-cpp:rocm714`.
- llama.cpp commit: `9723942adc518b43c4b95dc4dce6906903eb5e09`.
- llama.cpp build: `9723942ad (10711)`.
- HIP build option: `GGML_HIP_ROCWMMA_FATTN=ON`.
- Model: `unsloth/Qwen3.8-27B-GGUF`.
- Quantization: cached `Qwen3.8-27B-Q8_0.gguf`, 27.04 GiB, 27.32B parameters.
- Device report: each R9700 exposed 32,624 MiB VRAM; the container saw 65,248 MiB total.

All llama-bench runs used the same model, `--tensor-split 1/1`, `-ngl 999`, prompt lengths 128/512/2048/8192, generation length 128, batch size 2048, ubatch size 512, and three repetitions. The benchmark ran inside the interactive container with only the two R9700s visible.

## llama-bench baseline

Command shape:

```bash
HIP_VISIBLE_DEVICES=0,3 ./interactive-server.sh --detach

docker exec --user llama rocm-llama-interactive llama-bench \
  --hf-repo unsloth/Qwen3.8-27B-GGUF \
  --offline \
  --split-mode layer|tensor \
  --tensor-split 1/1 \
  -ngl 999 \
  -p 128,512,2048,8192 \
  -n 128 \
  -b 2048 \
  -ub 512 \
  -r 3 \
  -fa on|off \
  --cache-type-k f16 \
  --cache-type-v f16 \
  -o md
```

The benchmark's tensor mode has a constraint: llama.cpp rejects tensor mode when Flash Attention is off (`SPLIT_MODE_TENSOR requires flash_attn to be enabled`). Therefore the valid FA off/on comparison uses layer mode. Tensor mode is reported separately as the production-style configuration.

| Split mode | FA | KV | pp128 | pp512 | pp2048 | pp8192 | tg128 |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| layer | off | f16 | 887.74 ± 142.23 | 1297.31 ± 42.54 | 2007.92 ± 2.20 | 2096.11 ± 6.47 | 19.36 ± 0.01 |
| layer | on | f16 | 909.96 ± 99.38 | 1290.33 ± 39.22 | 1982.93 ± 3.87 | 2040.03 ± 4.29 | 19.52 ± 0.01 |
| tensor | on | f16 | 1097.09 ± 109.48 | 1706.48 ± 1.82 | 1609.98 ± 2.52 | 1497.09 ± 2.28 | 28.94 ± 0.12 |
| tensor | on | q8_0 | 1095.02 ± 109.33 | 1694.31 ± 0.91 | 1599.64 ± 0.39 | 1490.10 ± 2.25 | 28.68 ± 0.09 |

### Baseline interpretation

- In layer mode, enabling native ROCWMMA Flash Attention did not produce a meaningful improvement in this run. It was slightly faster at pp128 and tg128, and slightly slower at pp512, pp2048, and pp8192.
- Tensor mode with Flash Attention was faster for generation than layer mode: 28.94 versus 19.52 tok/s, approximately 48% higher. This is a split-mode result, not an isolated AITER or Flash Attention result.
- Tensor mode had higher prompt throughput at pp128 and pp512 but lower throughput at pp2048 and pp8192 than layer mode. The split-mode choice interacts with prompt length and should not be generalized from one row.
- Tensor-mode F16 and Q8 KV results were close through 8192 prompt tokens. The pasted Reddit F16-versus-Q8 advantage was measured with Vulkan, MTP, and much longer contexts, so it is a useful hypothesis but not reproduced by this short ROCm run.

## AITER feasibility

The supplied Reddit capture describes a patched vLLM ROCm-wheel recipe, not llama.cpp. It enables AITER unified attention with settings including `VLLM_ROCM_USE_AITER=1` and `VLLM_ROCM_USE_AITER_UNIFIED_ATTENTION=1`. That path is out of scope because this experiment is llama.cpp-only.

The llama.cpp-only probes were:

```bash
docker run --rm --entrypoint /bin/bash rocm-llama-cpp:rocm714 -lc '
  python3 - <<'PY'
import importlib.util
print(importlib.util.find_spec("aiter"))
PY
  python3 -m pip show aiter
'

strings /usr/local/bin/llama/llama-server | grep -i aiter
```

Results:

- `importlib.util.find_spec("aiter")` returned `None`.
- `pip show aiter` reported `Package(s) not found: aiter`.
- No AITER strings were found in `llama-server`.
- The current llama.cpp build does contain the native ROCWMMA path and successfully serves with `--flash-attn on`.

Decision: AITER is **not integrated into this llama.cpp image**. Porting an external AITER kernel into llama.cpp would be a new backend implementation, not an evidence-backed build flag. It was not attempted.

Relevant evidence:

- [ROCm/aiter issue #3294](https://github.com/ROCm/aiter/issues/3294): gfx1201/R9700 support is still WIP, with Triton first and HIP/flyDSL kernels later.
- [ROCm/aiter issue #1436](https://github.com/ROCm/aiter/issues/1436): unsupported-architecture experimentation requires care and should not be treated as native support.
- [llama.cpp native ROCWMMA build path](https://github.com/ggml-org/llama.cpp): this image uses `GGML_HIP_ROCWMMA_FATTN=ON`.

## Native MTP experiment

The Qwen3.8-27B GGUF metadata confirmed native MTP material:

```text
qwen35.nextn_predict_layers = 1
blk.64.nextn.eh_proj.weight
blk.64.nextn.enorm.weight
blk.64.nextn.hnorm.weight
blk.64.nextn.embed_tokens.weight
blk.64.nextn.shared_head_head.weight
```

`llama-bench` does not currently expose native speculative/MTP settings, so MTP was measured through llama-server's returned `timings` fields. Both arms used:

```text
HIP_VISIBLE_DEVICES=0,3
--split-mode tensor --tensor-split 1,1
--ctx-size 4096
--flash-attn on
--cache-type-k f16 --cache-type-v f16
--parallel 1 --no-cache-prompt
```

The baseline used `--spec-type none`. The MTP arms used `--spec-type draft-mtp` with `--spec-draft-n-max 2` or `3`. Each arm had one warmup request followed by three requests with `max_tokens=128`, temperature 0, and equivalent prompts.

| Arm | Generation timing | Mean generation rate | Draft acceptance |
| --- | ---: | ---: | ---: |
| no MTP | 4411--4416 ms for 128 tokens | 28.78 tok/s | n/a |
| MTP, n-max 2 | 2259--2300 ms for 128 tokens | 55.85 tok/s | approximately 0.77 after warmup |
| MTP, n-max 3 | 2089--2120 ms for 128 tokens | 60.40 tok/s | approximately 0.65--0.69 |
| MTP, n-max 3, 256k context, Q8 KV | one 16-token smoke request: 359.9 ms | 41.68 tok/s | 10/14 draft tokens accepted |
| MTP, n-max 3, 256k context, F16 KV | one 16-token smoke request: 268.9 ms | 55.78 tok/s | 11/12 draft tokens accepted |

The MTP server logs reported valid draft acceptance and `mean len` values. The API returned valid completions for all measured arms. No GPU reset, crash, or OOM occurred.

MTP n-max 3 was approximately 2.10x the no-MTP generation rate in this test. N-max 2 was approximately 1.94x. The n-max 3 result is faster despite lower acceptance because the accepted draft lengths and scheduling overhead produced a better total rate for this workload.

Limitations:

- The repeated MTP throughput comparison used 4096 context. Separate 262,144-context runs with Q8 and FP16 KV caches validated startup and one short request only.
- It used API timing rather than llama-bench because llama-bench has no MTP option in this build.
- It used one server slot and short repeated prompts, not concurrent serving.
- Output correctness was checked for valid responses, not against a long-form quality benchmark.
- The pasted Reddit MTP=3 result belongs to a patched vLLM configuration and is not directly comparable to these llama.cpp results.

## Final recommendation

Keep the current ROCm 7.14 llama.cpp image and native ROCWMMA build. Do not add AITER: there is no llama.cpp AITER integration in the pinned source or image, and the current AITER gfx1201 support is not mature enough to justify an unsupported port. Use tensor split plus native Flash Attention for dual-R9700 generation workloads, subject to prompt-length testing. Native embedded MTP is worth using for single-slot generation; both Q8 and FP16 KV variants initialized at 256k and served smoke requests, but full long-context acceptance and throughput remain unmeasured.

No AITER performance improvement was proven, so no AITER commit was created.
