# TranslateGemma llama-server Docker

Production-ready Docker project for running TranslateGemma with `llama-server`.

This repository is a standalone deployment project:
- no FastAPI runtime
- no Python inference wrapper
- single runtime process: `llama-server`

It is optimized for RTX 3080 Ti 12GB with:
- model: `steampunque/translategemma-12b-it-MP-GGUF`
- quant: `translategemma-12b-it.Q4_K_H.gguf`
- multimodal projector: `translategemma-12b-it.mmproj.gguf`

## Features

- OpenAI-compatible API: `POST /v1/chat/completions`
- Text + image translation
- Auto-detect `mmproj` and enable multimodal mode
- GPU Docker images for mainstream / legacy / future CUDA
- Built-in `docker compose` workflow
- Includes fix path for TranslateGemma language input (PR #19052)

## Quick Start (Recommended)

### 1) Download model files

```powershell
./scripts/download-model.ps1 -ModelRoot "D:/models/translategemma-12b-it-MP-GGUF"
```

### 2) Start with Docker Compose

```powershell
docker compose up -d --build
docker compose logs -f
```

### 3) Verify service

```powershell
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/v1/models
```

### 4) Stop service

```powershell
docker compose down
```

## Model Directory Layout

Host model root defaults to `D:/models`, mounted to `/models` in container.

```text
D:/models/
  translategemma-12b-it-MP-GGUF/
    translategemma-12b-it.Q4_K_H.gguf
    translategemma-12b-it.mmproj.gguf
```

`MODEL_NAME` must match the folder name under `/models`.

## Build and Run Manually

### Build

```powershell
docker build -f MainstreamCudaDockerfile -t gemma-translate:mainstream-cuda .
```

### Run

```powershell
docker run --gpus all -d `
  --name tg-llama `
  -p 127.0.0.1:8080:8080 `
  -v D:/models:/models `
  -e MODEL_NAME=translategemma-12b-it-MP-GGUF `
  -e LLAMA_N_GPU_LAYERS=-1 `
  -e LLAMA_N_PARALLEL=2 `
  -e LLAMA_N_CTX=3072 `
  -e LLAMA_FLASH_ATTN=on `
  gemma-translate:mainstream-cuda
```

## Build an Image with Models Bundled

If you already built a base image such as `gemma-translate:mainstream-cuda`, and the model files are present under `scripts/models/`, you can use `BundledModelDockerfile` to create a second image layer that bakes the models into `/models`.

### Build

```powershell
docker build -f BundledModelDockerfile `
  --build-arg BASE_IMAGE=gemma-translate:mainstream-cuda `
  -t gemma-translate:mainstream-cuda-bundled .
```

### Run

```powershell
docker run --gpus all -d `
  --name tg-llama-bundled `
  -p 127.0.0.1:8080:8080 `
  -e MODEL_NAME=translategemma-12b-it-MP-GGUF `
  -e LLAMA_N_GPU_LAYERS=-1 `
  -e LLAMA_N_PARALLEL=2 `
  -e LLAMA_N_CTX=3072 `
  -e LLAMA_FLASH_ATTN=on `
  gemma-translate:mainstream-cuda-bundled
```

This image no longer needs a host-side `-v D:/models:/models` bind mount because the model files are stored directly in `/models/translategemma-12b-it-MP-GGUF/` inside the container.

## Build Parameters (Detailed)

### Docker build command parameters

- `-f <Dockerfile>`: choose which image recipe to build (`MainstreamCudaDockerfile`, `LegacyCudaDockerfile`, `FutureCudaDockerfile`, `Dockerfile`)
- `-t <image:tag>`: output image name and tag
- `--build-arg KEY=VALUE`: pass build-time args into Dockerfile
- `.`: build context (current folder)

Example:

```powershell
docker build -f MainstreamCudaDockerfile `
  -t gemma-translate:mainstream-cuda `
  --build-arg LLAMA_CPP_REF=master `
  --build-arg LLAMA_CUDA_ARCH=86 `
  .
```

### Dockerfile build args

- `LLAMA_CPP_REF`
  - meaning: which `llama.cpp` source ref to build (branch/tag/commit/refspec)
  - default: `master`
  - examples: `master`, `bXXXX`, `<commit_sha>`
- `LLAMA_CUDA_ARCH` (CUDA Dockerfiles only)
  - meaning: CUDA SM architectures passed to `-DCMAKE_CUDA_ARCHITECTURES`
  - default:
    - `MainstreamCudaDockerfile`: `86`
    - `LegacyCudaDockerfile`: `61`
    - `FutureCudaDockerfile`: `89;90;100;120`

### `LLAMA_CUDA_ARCH` value mapping

These numbers are CUDA **SM (compute capability) major/minor without dot**:

- `61` -> sm_61 (Pascal generation, common in GTX 10xx era cards)
- `75` -> sm_75 (Turing, e.g. RTX 20xx / T4)
- `80` -> sm_80 (Ampere datacenter, e.g. A100)
- `86` -> sm_86 (Ampere GA10x, e.g. RTX 30xx including 3080 Ti)
- `89` -> sm_89 (Ada Lovelace, e.g. RTX 40xx)
- `90` -> sm_90 (Hopper, e.g. H100/H200)
- `100` / `120` -> future/newer architectures (keep only if you really need cross-generation compatibility)

How to choose:

- single target GPU: set one value only (fastest build, smallest binary)
  - for RTX 3080 Ti, use `LLAMA_CUDA_ARCH=86`
- mixed GPU fleet: use semicolon-separated list, e.g. `86;89` (slower build, larger binary)

### CMake flags used in CUDA builds

- `-DGGML_CUDA=ON`: enable CUDA backend in ggml/llama.cpp
- `-DCMAKE_CUDA_ARCHITECTURES=...`: compile kernels for selected SM architectures
- `-DGGML_CUDA_FA_ALL_QUANTS=ON`: enable wider Flash-Attn quant kernel path (better runtime compatibility/perf, longer build time)
- `-DCMAKE_EXE_LINKER_FLAGS=...`: points linker to CUDA stub `libcuda` during CI build to avoid `libcuda.so.1 not found` link errors

## Client Request Demos

Important request format:
- text translation can keep using `chat_template_kwargs`
- image translation currently expects `messages[].content` to be an array with exactly one item
- that item should directly carry `type`, `source_lang_code`, `target_lang_code`, and `url`

### cURL (text)

```bash
curl -X POST "http://127.0.0.1:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "user",
        "content": "Where is the train station?"
      }
    ],
    "chat_template_kwargs": {
      "source_lang_code": "en",
      "target_lang_code": "zh"
    },
    "max_tokens": 200,
    "temperature": 0.2
  }'
```

### cURL (image)

```bash
curl -X POST "http://127.0.0.1:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "image",
            "source_lang_code": "en",
            "target_lang_code": "zh",
            "url": "https://huggingface.co/ggml-org/tinygemma3-GGUF/resolve/main/test/91_cat.png"
          }
        ]
      }
    ],
    "max_tokens": 500
  }'
```

### Python (requests)

```python
import requests

payload = {
    "messages": [
        {
            "role": "user",
            "content": "Please translate this sentence."
        }
    ],
    "chat_template_kwargs": {
        "source_lang_code": "en",
        "target_lang_code": "zh"
    },
    "max_tokens": 200,
    "temperature": 0.2,
}

resp = requests.post("http://127.0.0.1:8080/v1/chat/completions", json=payload, timeout=120)
resp.raise_for_status()
print(resp.json()["choices"][0]["message"]["content"])
```

### PowerShell (local image or image URL)

The repository also includes a ready-to-run image translation test script: `scripts/test-image-translate.ps1`

Local image example:

```powershell
./scripts/test-image-translate.ps1 `
  -ImagePath "D:/test-images/menu-en.png" `
  -SourceLangCode en `
  -TargetLangCode zh
```

Remote image example:

```powershell
./scripts/test-image-translate.ps1 `
  -ImageUrl "https://example.com/sample-sign.jpg" `
  -SourceLangCode auto `
  -TargetLangCode zh
```

## Configuration

### Compose variables

- `MODEL_ROOT` (default: `D:/models`): mounted to container path `/models`; if the host path is wrong, startup cannot find the model directory.
- `MODEL_NAME` (default: `translategemma-12b-it-MP-GGUF`): passed into runtime and selects `/models/<MODEL_NAME>`; also controls whether matching `*mmproj*.gguf` is auto-detected.
- `LLAMA_CPP_REF` (default: `master`): build-time source ref for `llama.cpp`; changing it rebuilds the image and may change supported flags, behavior, and performance.
- `LLAMA_N_GPU_LAYERS` (default: `-1` in compose): compose intentionally overrides entrypoint default `0`; `-1` tries to offload all layers to GPU, usually faster but uses the most VRAM.
- `LLAMA_N_PARALLEL` (default: `2` in compose): compose intentionally overrides entrypoint default `4`; lowers concurrency to save KV cache memory on 12 GB cards.
- `LLAMA_N_CTX` (default: `3072` in compose): compose intentionally overrides entrypoint default `2048`; gives a longer context window but reserves more memory.
- `LLAMA_FLASH_ATTN` (default: `on` in compose): enables flash attention by default on the mainstream image; can improve speed / memory efficiency when supported.
- `LLAMA_PORT` (fixed to `8080` in compose): container listens on `8080`, and compose maps `127.0.0.1:8080:8080`; if you change this, also update `ports` and the healthcheck URL.

### Runtime variables

- `MODEL_NAME` (required): selects `/models/<MODEL_NAME>` at startup. If the directory does not exist, or contains no non-`mmproj` `.gguf`, the container exits immediately. If a `*mmproj*.gguf` file is found in the same folder, image translation is enabled automatically; otherwise the server runs in text-only mode.
- `LLAMA_N_GPU_LAYERS` (mapped to `-ngl`, default `0`): controls how many transformer layers are offloaded to GPU. `0` means CPU-only execution, `-1` means try to offload all layers, and larger positive values increase GPU usage. Raising it usually improves speed but increases VRAM usage and can trigger OOM.
- `LLAMA_N_CTX` (mapped to `-c`, default `2048`): sets the context window size. Larger values allow longer prompts / more history, but increase KV cache memory usage even before traffic arrives; lowering it is usually the first fix for OOM.
- `LLAMA_N_PARALLEL` (mapped to `--parallel`, default `4`): sets how many decoding slots `llama-server` keeps for concurrent requests. This image always enables `--cont-batching`, so raising the value improves concurrency / throughput, but also multiplies KV cache pressure and reduces per-request memory headroom.
- `LLAMA_N_THREADS` (mapped to `-t`, optional): caps CPU worker threads for CPU-side work. Higher values can reduce latency until the CPU is saturated; too high can cause contention. If unset, `llama-server` chooses its own thread count.
- `LLAMA_FLASH_ATTN` (mapped to `--flash-attn`, default `on`; `LegacyCudaDockerfile` image default is `off`): accepted values are `on`, `off`, `auto`, plus boolean-like aliases (`1/0`, `true/false`, `yes/no`). Invalid values cause the entrypoint to exit before starting the server. `on` prefers flash attention, `off` disables it, and `auto` leaves the final decision to `llama-server`.
- `LLAMA_PORT` (mapped to `--port`, default `8080`): changes the listening port inside the container. For manual `docker run`, the host-side `-p` mapping must match it; for compose, also update `ports` and the healthcheck.
- `LLAMA_EXTRA_ARGS` (optional): appended verbatim after the built-in arguments when launching `llama-server`. Use this for advanced flags not exposed by the image. Because the script splits on spaces, quoting with embedded spaces is fragile; if you repeat a flag already set earlier, the later value may override the earlier one depending on `llama-server` parsing.

## GitHub CI/CD

This repo includes GitHub Actions workflows:

- `.github/workflows/ci.yml`
  - validates `compose.yaml`
  - builds CPU image as smoke test
- `.github/workflows/build-and-push-ghcr.yml`
  - builds images and pushes to GHCR
  - supports `mainstream / legacy / future / cpu / all` variants
  - supports custom `LLAMA_CPP_REF` (default `master`)
  - on `main`/tag push, auto-builds `mainstream` only (cost control)

### How to use

1. Push the project to a GitHub repository.
2. Open `Actions` -> `Build And Push GHCR` -> `Run workflow`.
3. Select `variant` (recommend `mainstream`) and keep `push=true`.
4. After success, pull image from:
   - `ghcr.io/<your-org-or-user>/translategemma-llama-server:<tag>`

### Example pull/run

```bash
docker pull ghcr.io/<your-org-or-user>/translategemma-llama-server:mainstream-latest
docker run --gpus all -d \
  -p 127.0.0.1:8080:8080 \
  -v D:/models:/models \
  -e MODEL_NAME=translategemma-12b-it-MP-GGUF \
  ghcr.io/<your-org-or-user>/translategemma-llama-server:mainstream-latest
```

For faster and more stable CUDA builds, a self-hosted runner is recommended.

## Tuning Tips (3080 Ti 12GB)

If OOM happens:
1. reduce `LLAMA_N_CTX` first (for example `2048`)
2. reduce `LLAMA_N_GPU_LAYERS` (for example `40`)
3. reduce `LLAMA_N_PARALLEL` from `2` to `1`

## Project Files

```text
entrypoint.sh
compose.yaml
Dockerfile
BundledModelDockerfile
MainstreamCudaDockerfile
LegacyCudaDockerfile
FutureCudaDockerfile
scripts/download-model.ps1
README.md
README.zh-CN.md
```

## Notes

- For TranslateGemma language handling compatibility, this project defaults to a llama.cpp ref including PR #19052:
  https://github.com/ggml-org/llama.cpp/pull/19052
- Chinese documentation: `README.zh-CN.md`
