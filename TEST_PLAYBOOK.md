# Test playbook

The old staged playbook described commands and image paths that no longer match the current Dockerfile and launchers. The authoritative tests now live beside the operational procedures:

[Open the operations guide and test cases](docs/OPERATIONS.md)

The guide covers:

1. Persistent image builds.
2. Interactive Bash access.
3. Graceful detached-container shutdown.
4. Versioned rebuilds and rollback by image tag.
5. `llama-bench` model-performance checks using `unsloth/Qwen3.5-2B-GGUF`.
6. GPU selection with `HIP_VISIBLE_DEVICES`.

Run the tests from `rocm_docker/` and use the model and GPU set appropriate for the host.
