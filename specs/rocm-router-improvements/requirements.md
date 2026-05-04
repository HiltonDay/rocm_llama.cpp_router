# Requirements Document

## Introduction

This feature delivers a staged, iterative approach to building a Docker-based multi-model inference server using llama.cpp with ROCm (AMD GPU) support. The llama.cpp build and model configuration are proven working on a manually-built container using the same base image. All work is environmental — permissions, groups, filesystem mounts, environment variables, GPU device access, and container orchestration.

The four stages progress from interactive debugging through scripted startup to auto-start and finally production router mode. Each stage must be proven working before advancing. All stages produce documented manual test cases so a human operator can follow the process without AI assistance. Progression between stages is achieved by uncommenting pre-written code and scripts.

## Glossary

- **Container**: The Docker container running the llama.cpp server image
- **Image**: The Docker image built from the Dockerfile, containing the compiled llama-server binary and ROCm libraries
- **Host**: The physical machine running Docker, with AMD GPUs and pre-downloaded models
- **llama-server**: The llama.cpp HTTP inference server binary, compiled with ROCm/HIP support
- **Router_Mode**: llama-server operating as a model dispatcher using --models-preset, loading and unloading models on request
- **ROCm**: AMD's open-source GPU compute platform (Radeon Open Compute)
- **HIP**: AMD's GPU programming interface used by ROCm, analogous to CUDA
- **GPU_Devices**: The /dev/kfd and /dev/dri device nodes required for ROCm GPU access
- **HF_Cache**: The HuggingFace model cache directory on the host (~/.cache/huggingface/), bind-mounted into the container
- **Models_INI**: The INI configuration file (/etc/llama-server/models.ini) defining per-model settings for router mode
- **Run_Script**: The shell script (run-server.sh) that launches the container with security hardening flags
- **Entrypoint**: The container entrypoint script that sets up XDG directories, drops privileges, and executes llama-server
- **Llama_User**: The non-root user (llama) inside the container, member of video and render groups for GPU access
- **Debug_Shell**: An interactive shell session inside the container running as Llama_User with all environment variables set
- **Stage_Gate**: A documented set of manual verification steps that must all pass before progressing to the next stage
- **Test_Playbook**: A complete set of console commands and expected outputs documenting how to verify each stage

## Requirements

### Requirement 1: Docker Image Build

**User Story:** As a developer, I want to build the Docker image with ROCm support and llama.cpp compiled for my GPU architectures, so that I have a working base image for all subsequent stages.

#### Acceptance Criteria

1. WHEN the Dockerfile is built, THE Image SHALL compile llama-server from the pinned commit (63d93d17336e41e4cc73a64451e5b1d2477abdb1) with GGML_HIP=ON targeting gfx908 and gfx1100 architectures
2. WHEN the Dockerfile is built, THE Image SHALL create Llama_User with membership in the video and render groups
3. WHEN the Dockerfile is built, THE Image SHALL install the llama-server binary at /usr/local/bin/llama/llama-server with all required shared libraries in the same directory
4. WHEN the Dockerfile is built, THE Image SHALL copy Models_INI to /etc/llama-server/models.ini
5. WHEN the Dockerfile is built, THE Image SHALL set LD_LIBRARY_PATH to include /usr/local/bin/llama and HF_HOME to /huggingface
6. IF the Docker build fails, THEN THE Image SHALL produce a build log identifying the failing step and error message

### Requirement 2: Stage 1 — Interactive Debug Image

**User Story:** As a developer, I want to log into the container as Llama_User with all environment variables set and GPU access available, so that I can manually start llama-server and debug the environment before automating anything.

#### Acceptance Criteria

1. WHEN Run_Script launches the Container in Stage 1 mode, THE Container SHALL start with an interactive shell as Llama_User instead of auto-starting llama-server
2. WHILE the Container is running in Stage 1 mode, THE Container SHALL have /dev/kfd and /dev/dri device nodes accessible to Llama_User
3. WHILE the Container is running in Stage 1 mode, THE Container SHALL have Llama_User as a member of the video and render groups with confirmed group membership via the `id` command
4. WHILE the Container is running in Stage 1 mode, THE Container SHALL have HF_Cache bind-mounted at /huggingface with read access for Llama_User
5. WHILE the Container is running in Stage 1 mode, THE Container SHALL have the models directory bind-mounted at /models with read-only access for Llama_User
6. WHILE the Container is running in Stage 1 mode, THE Container SHALL have XDG_CACHE_HOME, XDG_CONFIG_HOME, and XDG_DATA_HOME set to writable directories under /tmp
7. WHILE the Container is running in Stage 1 mode, THE Container SHALL have LD_LIBRARY_PATH set to include /usr/local/bin/llama so that llama-server can locate its shared libraries
8. WHEN Llama_User manually invokes llama-server with a model path, THE llama-server SHALL detect and use the AMD GPU devices
9. WHEN Llama_User manually invokes llama-server with a model from HF_Cache, THE llama-server SHALL load the model into GPU VRAM and respond to HTTP requests on the specified port
10. THE Test_Playbook for Stage 1 SHALL document console commands to verify: GPU device access, environment variables, file permissions on model mounts, HF_Cache read access, library paths, group membership, and manual llama-server invocation

### Requirement 3: Stage 2 — Script-Initiated Server with Debug Access

**User Story:** As a developer, I want Run_Script to start llama-server on container launch while retaining the ability to exec into the running container for debugging, so that I can verify the server runs correctly under scripted conditions.

#### Acceptance Criteria

1. WHEN Run_Script launches the Container in Stage 2 mode, THE Run_Script SHALL start llama-server via a startup command passed to the container, binding to 127.0.0.1 on port 8000
2. WHILE the Container is running in Stage 2 mode, THE Container SHALL allow a developer to exec into the running container as Llama_User with all environment variables preserved
3. WHILE the Container is running in Stage 2 mode, THE Container SHALL expose llama-server logs accessible via `docker logs`
4. WHEN a developer execs into the running Container, THE Debug_Shell SHALL have access to commands for checking: folder permissions, environment variables, GPU device status, server process status, and memory allocations
5. WHILE the Container is running in Stage 2 mode, THE Container SHALL maintain the same security hardening as Stage 1: read-only filesystem, tmpfs at /tmp, no-new-privileges, and non-root execution
6. WHEN llama-server is started by Run_Script, THE llama-server SHALL accept HTTP requests at http://127.0.0.1:8000/v1/models and return a valid response
7. IF llama-server fails to start, THEN THE Container SHALL remain running so the developer can exec in and diagnose the failure
8. THE Test_Playbook for Stage 2 SHALL document console commands to verify: server process status, log inspection, HTTP endpoint responses, GPU memory usage, folder permissions, environment variables, and exec-based debugging

### Requirement 4: Stage 3 — Auto-Start Server Image

**User Story:** As a developer, I want the Docker image to auto-start llama-server via ENTRYPOINT/CMD when the container starts, so that the server runs automatically on container start/stop without manual intervention.

#### Acceptance Criteria

1. WHEN the Container starts in Stage 3 mode, THE Entrypoint SHALL automatically drop privileges to Llama_User and start llama-server with the configured arguments
2. WHEN the Container starts in Stage 3 mode, THE llama-server SHALL bind to 127.0.0.1 on port 8000 using --network host
3. WHILE the Container is running in Stage 3 mode, THE Container SHALL be stoppable via `docker stop` and restartable via `docker start` with llama-server resuming automatically
4. WHILE the Container is running in Stage 3 mode, THE Container SHALL allow exec-based debug access as Llama_User
5. WHILE the Container is running in Stage 3 mode, THE Container SHALL maintain all security hardening: read-only filesystem, tmpfs at /tmp, no-new-privileges, non-root execution, and read-only model mounts
6. WHEN the Container is started with `docker run`, THE Entrypoint SHALL set up XDG directories under /tmp before starting llama-server
7. IF llama-server exits unexpectedly, THEN THE Container SHALL stop with a non-zero exit code visible via `docker inspect`
8. THE Test_Playbook for Stage 3 SHALL document console commands to verify: automatic server startup, stop/start cycle, HTTP endpoint availability after restart, log inspection, and exec-based debugging

### Requirement 5: Stage 4 — Production Router Mode

**User Story:** As a developer, I want llama-server to run in router mode with models-preset, supporting dynamic model loading and unloading, so that chat interfaces and tools can switch between models and the server handles load/unload automatically.

#### Acceptance Criteria

1. WHEN the Container starts in Stage 4 mode, THE llama-server SHALL start in Router_Mode using --models-preset pointing to Models_INI
2. WHEN the Container starts in Stage 4 mode, THE llama-server SHALL use --models-max 1 to load one model at a time in swap mode
3. WHEN a client sends a chat completion request specifying a model name, THE llama-server SHALL load the requested model if it is not already loaded, unloading the current model first if necessary
4. WHEN a model swap occurs, THE llama-server SHALL complete the swap within the expected timeframe (approximately 3-10 seconds depending on model size)
5. WHEN the Container starts in Stage 4 mode, THE llama-server SHALL respond to GET /v1/models with a list of all models defined in Models_INI
6. WHEN a client sends a chat completion request for a model not defined in Models_INI, THE llama-server SHALL return an appropriate error response
7. WHILE the Container is running in Stage 4 mode, THE Container SHALL maintain all security hardening from Stage 3
8. WHEN the first model specified with load-on-startup = true in Models_INI is requested, THE llama-server SHALL load that model on the first request or at startup depending on --models-autoload configuration
9. THE Test_Playbook for Stage 4 SHALL document console commands to verify: model listing, chat completion with each model, model swap behaviour, swap timing, error handling for unknown models, and concurrent request behaviour during swap

### Requirement 6: Staged Progression Mechanism

**User Story:** As a developer, I want all code and scripts for later stages to be present but commented out from the start, so that I can progress between stages by uncommenting code rather than writing new code.

#### Acceptance Criteria

1. THE Dockerfile SHALL contain commented-out sections for Stage 3 and Stage 4 ENTRYPOINT/CMD configurations, with clear comments indicating which stage each section belongs to
2. THE Run_Script SHALL contain commented-out sections for each stage's docker run invocation, with clear comments indicating which stage each section belongs to and instructions for switching
3. THE Entrypoint SHALL contain commented-out sections for Stage 2 server startup logic and Stage 4 router mode arguments, with clear comments indicating which stage each section belongs to
4. WHEN a developer uncomments the Stage N sections and comments out the Stage N-1 sections, THE system SHALL function correctly for Stage N without additional code changes
5. THE Run_Script SHALL include inline comments documenting the purpose of each security flag and mount option

### Requirement 7: Test Playbook Documentation

**User Story:** As a developer, I want complete manual test documentation for every stage, so that someone can follow the verification process without AI assistance.

#### Acceptance Criteria

1. THE Test_Playbook SHALL be a single document covering all four stages with clear stage boundaries
2. THE Test_Playbook for each stage SHALL list every console command needed for verification, with the expected output or success criteria for each command
3. THE Test_Playbook SHALL include a pre-flight checklist covering: host prerequisites (ROCm driver, Docker, GPU devices), model pre-download verification, and image build verification
4. THE Test_Playbook SHALL include troubleshooting guidance for common failures: GPU device permission errors, library path issues, mount permission errors, and port binding failures
5. WHEN a Stage_Gate verification step fails, THE Test_Playbook SHALL provide diagnostic commands to identify the root cause
6. THE Test_Playbook SHALL document the exact commands to progress from one stage to the next (which lines to comment/uncomment in which files)

### Requirement 8: ROCm GPU Access Configuration

**User Story:** As a developer, I want the container to have correct GPU device access and group membership, so that llama-server can use the AMD GPUs for inference.

#### Acceptance Criteria

1. WHEN Run_Script launches the Container, THE Run_Script SHALL pass --device /dev/kfd and --device /dev/dri to expose GPU devices to the container
2. WHEN Run_Script launches the Container, THE Run_Script SHALL pass --group-add video and --group-add render to grant GPU access groups to the container process
3. WHILE the Container is running, THE Llama_User SHALL have effective membership in the video and render groups as confirmed by the `id` command
4. WHILE the Container is running, THE Llama_User SHALL have read-write access to /dev/kfd and /dev/dri device nodes
5. IF GPU_Devices are not accessible inside the Container, THEN THE Test_Playbook SHALL provide diagnostic commands to check: device node existence, device permissions, group membership, and ROCm driver status on the Host

### Requirement 9: Security Hardening

**User Story:** As a developer, I want the container to follow defense-in-depth security principles, so that the inference server runs with minimal attack surface.

#### Acceptance Criteria

1. WHEN Run_Script launches the Container, THE Run_Script SHALL use --read-only to make the container filesystem immutable
2. WHEN Run_Script launches the Container, THE Run_Script SHALL mount a tmpfs at /tmp with rw,noexec,nosuid permissions and a size limit of 64MB
3. WHEN Run_Script launches the Container, THE Run_Script SHALL use --security-opt no-new-privileges:true to prevent privilege escalation
4. WHEN Run_Script launches the Container, THE Run_Script SHALL use --network host with llama-server bound to 127.0.0.1 to restrict access to localhost only
5. WHEN Run_Script launches the Container, THE Run_Script SHALL mount HF_Cache with the z SELinux label for shared access
6. WHEN Run_Script launches the Container, THE Run_Script SHALL mount the models directory as read-only with the z SELinux label
7. THE Entrypoint SHALL drop all inheritable capabilities via setpriv --inh-caps=-all when executing llama-server
8. THE Entrypoint SHALL use setpriv with --init-groups to rebuild supplementary groups from /etc/group for GPU access

### Requirement 10: Filesystem Mount Configuration

**User Story:** As a developer, I want the host model cache and models directory correctly mounted into the container, so that llama-server can access pre-downloaded models without network access.

#### Acceptance Criteria

1. WHEN Run_Script launches the Container, THE Run_Script SHALL bind-mount the host HF_Cache directory (defaulting to $HOME/.cache/huggingface) to /huggingface inside the Container
2. WHEN Run_Script launches the Container, THE Run_Script SHALL bind-mount the host models directory (defaulting to $HOME/models) to /models inside the Container as read-only
3. WHILE the Container is running, THE Llama_User SHALL have read access to GGUF model files within /huggingface
4. WHILE the Container is running, THE Llama_User SHALL have read access to files within /models
5. IF the host HF_Cache directory does not exist, THEN THE Run_Script SHALL create it before launching the Container
6. IF the host models directory does not exist, THEN THE Run_Script SHALL create it before launching the Container
7. WHILE the Container is running with a read-only filesystem, THE Container SHALL have writable tmpfs at /tmp for XDG directories and temporary files needed by llama-server
