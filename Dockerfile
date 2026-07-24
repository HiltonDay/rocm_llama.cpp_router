FROM docker.io/rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0

# b10106 - latest stable release, includes MTP (merged b9235), multi-GPU layer split,
# flash attention with rocWMMA, and all recent HIP/ROCm fixes for gfx1201
ARG LLAMA_CPP_COMMIT=b10106

RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    cmake \
    git \
    libssl-dev \
    gosu \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/ggml-org/llama.cpp.git /llama.cpp \
    && cd /llama.cpp \
    && git checkout $LLAMA_CPP_COMMIT

WORKDIR /llama.cpp

ENV LLAMACPP_ROCM_ARCH="gfx908,gfx1100,gfx1201"

RUN cmake -S . -B build \
      -DCMAKE_C_COMPILER=/opt/rocm/llvm/bin/clang \
      -DCMAKE_CXX_COMPILER=/opt/rocm/llvm/bin/clang++ \
      -DGGML_HIP=ON \
      -DGGML_HIP_ROCWMMA_FATTN=ON \
      -DAMDGPU_TARGETS=$LLAMACPP_ROCM_ARCH \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLAMA_CURL=ON \
      -DLLAMA_OPENSSL=ON \
    && cmake --build build --config Release -j$(nproc)

RUN mkdir -p /usr/local/bin/llama \
    && cp build/bin/llama-server /usr/local/bin/llama/llama-server \
    && cp build/bin/llama-bench /usr/local/bin/llama/llama-bench \
    && find build -name "*.so*" -exec cp -P {} /usr/local/bin/llama/ \; \
    && rm -rf /llama.cpp

RUN pip install huggingface_hub hf_transfer \
    && pip cache purge

ENV PATH=/usr/local/bin/llama:/opt/venv/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/bin/llama:$LD_LIBRARY_PATH
ENV HF_HOME=/home/llama/.cache/huggingface

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

COPY models.ini /etc/llama-server/models.ini

RUN groupadd -r video 2>/dev/null; groupadd -r render 2>/dev/null; \
    groupadd -r llama && \
    useradd -r -g llama -G video,render -d /models -s /bin/bash llama

WORKDIR /

EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["/usr/local/bin/llama/llama-server", "--models-preset", "/etc/llama-server/models.ini", "--models-max", "1", "--host", "0.0.0.0", "--port", "8000"]
