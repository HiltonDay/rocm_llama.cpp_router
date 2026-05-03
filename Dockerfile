FROM rocm/pytorch:rocm7.2.2_ubuntu24.04_py3.12_pytorch_release_2.10.0

ARG LLAMA_CPP_COMMIT=63d93d17336e41e4cc73a64451e5b1d2477abdb1

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

ENV LLAMACPP_ROCM_ARCH="gfx908,gfx1100"

RUN HIPCXX="$(hipconfig -l)/clang" \
    HIP_PATH="$(hipconfig -R)" \
    cmake -S . -B build \
      -DGGML_HIP=ON \
      -DGGML_HIP_ROCWMMA_FATTN=ON \
      -DAMDGPU_TARGETS=$LLAMACPP_ROCM_ARCH \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLAMA_CURL=ON \
      -DLLAMA_OPENSSL=ON \
    && cmake --build build --config Release -j$(nproc)

RUN mkdir -p /usr/local/bin/llama \
    && cp build/bin/llama-server /usr/local/bin/llama/llama-server \
    && find build -name "*.so*" -exec cp -P {} /usr/local/bin/llama/ \; \
    && rm -rf /llama.cpp

RUN pip install huggingface_hub hf_transfer \
    && pip cache purge

ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/bin/llama
ENV HF_HOME=/huggingface

COPY models.ini /etc/llama-server/models.ini

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER root
WORKDIR /huggingface

EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--models-preset", "/etc/llama-server/models.ini", "--host", "0.0.0.0", "--port", "8000"]
