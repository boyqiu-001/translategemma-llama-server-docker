FROM ubuntu:22.04

ARG LLAMA_CPP_REF=master

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    cmake \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp.git /tmp/llama.cpp \
    && cd /tmp/llama.cpp \
    && if [ "${LLAMA_CPP_REF}" != "master" ]; then git fetch --depth 1 origin "${LLAMA_CPP_REF}" && git checkout FETCH_HEAD; fi \
    && cmake -S /tmp/llama.cpp -B /tmp/llama.cpp/build \
       -DCMAKE_BUILD_TYPE=Release \
       -DGGML_NATIVE=OFF \
       -DGGML_OPENMP=ON \
    && cmake --build /tmp/llama.cpp/build --config Release -t llama-server -j"$(nproc)" \
    && find /tmp/llama.cpp/build -maxdepth 3 \( -type f -o -type l \) -name 'lib*.so*' -exec cp -a {} /usr/local/lib/ \; \
    && cp /tmp/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server \
    && ldconfig \
    && rm -rf /tmp/llama.cpp

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
