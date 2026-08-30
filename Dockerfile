FROM docker.io/rocm/dev-ubuntu-24.04:7.14.0-full AS llama-builder

# Upstream llama.cpp master as resolved on 2026-08-30.
ARG LLAMA_CPP_COMMIT=9723942adc518b43c4b95dc4dce6906903eb5e09

RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    cmake \
    git \
    libssl-dev \
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
      -DLLAMA_OPENSSL=ON \
    && cmake --build build --config Release -j$(nproc)

RUN mkdir -p /usr/local/bin/llama \
    && cp build/bin/llama-server /usr/local/bin/llama/llama-server \
    && cp build/bin/llama-bench /usr/local/bin/llama/llama-bench \
    && find build -name "*.so*" -exec cp -P {} /usr/local/bin/llama/ \; \
    && rm -rf /llama.cpp

FROM docker.io/rocm/pytorch:rocm7.14_ubuntu24.04_py3.12_pytorch_release_2.12.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    gosu \
    && rm -rf /var/lib/apt/lists/*

COPY --from=llama-builder /usr/local/bin/llama /usr/local/bin/llama

RUN pip install huggingface_hub hf_transfer \
    && pip cache purge

ENV PATH=/usr/local/bin/llama:/opt/venv/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/bin/llama:/opt/venv/lib/python3.12/site-packages/_rocm_sdk_core/lib:/opt/venv/lib/python3.12/site-packages/_rocm_sdk_core/lib/llvm/lib:/opt/venv/lib/python3.12/site-packages/_rocm_sdk_libraries/lib:$LD_LIBRARY_PATH
ENV HF_HOME=/home/llama/.cache/huggingface
ENV HOME=/home/llama
ENV HISTFILE=/home/llama/.bash_history
ENV HISTSIZE=10000
ENV HISTFILESIZE=20000

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

COPY models.ini /etc/llama-server/models.ini

RUN groupadd -r video 2>/dev/null; groupadd -r render 2>/dev/null; \
    groupadd -r llama && \
    useradd -r -g llama -G video,render -d /home/llama -s /bin/bash llama && \
    mkdir -p /home/llama && \
    chown llama:llama /home/llama

WORKDIR /

EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["/usr/local/bin/llama/llama-server", "--models-preset", "/etc/llama-server/models.ini", "--models-max", "1", "--host", "0.0.0.0", "--port", "8000"]
