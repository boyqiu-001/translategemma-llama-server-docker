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

## Client Request Demos

Important request format:
- language fields go in `chat_template_kwargs`
- text can be plain string in `messages[].content`
- image uses OpenAI-style `image_url`

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
            "type": "image_url",
            "image_url": {
              "url": "https://huggingface.co/ggml-org/tinygemma3-GGUF/resolve/main/test/91_cat.png"
            }
          }
        ]
      }
    ],
    "chat_template_kwargs": {
      "source_lang_code": "en",
      "target_lang_code": "zh"
    },
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

## Configuration

### Compose variables

- `MODEL_ROOT` (default: `D:/models`)
- `MODEL_NAME` (default: `translategemma-12b-it-MP-GGUF`)
- `LLAMA_CPP_REF` (default: `refs/pull/19052/head`)
- `LLAMA_N_GPU_LAYERS` (default: `-1` in compose)
- `LLAMA_N_PARALLEL` (default: `2` in compose)
- `LLAMA_N_CTX` (default: `3072` in compose)

### Runtime variables

- `MODEL_NAME` (required)
- `LLAMA_N_GPU_LAYERS` (default `0`)
- `LLAMA_N_CTX` (default `2048`)
- `LLAMA_N_PARALLEL` (default `4`)
- `LLAMA_N_THREADS` (optional)
- `LLAMA_FLASH_ATTN` (default `on`)
- `LLAMA_PORT` (default `8080`)
- `LLAMA_EXTRA_ARGS` (optional)

## GitHub CI/CD

This repo includes GitHub Actions workflows:

- `.github/workflows/ci.yml`
  - validates `compose.yaml`
  - builds CPU image as smoke test
- `.github/workflows/build-and-push-ghcr.yml`
  - builds images and pushes to GHCR
  - supports `mainstream / legacy / future / cpu / all` variants
  - supports custom `LLAMA_CPP_REF` (default `refs/pull/19052/head`)
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
