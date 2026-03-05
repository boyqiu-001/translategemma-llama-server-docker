# TranslateGemma llama-server Docker（独立项目）

这是一个可直接部署的 TranslateGemma Docker 项目，运行时仅包含 `llama-server`。

项目目标：
- 不依赖 FastAPI 运行时
- 不使用 Python 推理封装层
- 直接对外提供 OpenAI 兼容接口

默认针对 RTX 3080 Ti 12GB 优化：
- 模型仓库：`steampunque/translategemma-12b-it-MP-GGUF`
- Q4 模型：`translategemma-12b-it.Q4_K_H.gguf`
- 多模态投影：`translategemma-12b-it.mmproj.gguf`

## 功能特性

- OpenAI 兼容接口：`POST /v1/chat/completions`
- 支持文本翻译和图片翻译
- 自动检测 `mmproj`，自动开启多模态
- 提供多套 Dockerfile（主流 CUDA / 旧卡 CUDA / 新架构 CUDA / CPU）
- 提供 `docker compose` 一键启动
- 默认兼容 TranslateGemma 语言参数修复（PR #19052）

## 快速开始（推荐）

### 1）下载模型

```powershell
./scripts/download-model.ps1 -ModelRoot "D:/models/translategemma-12b-it-MP-GGUF"
```

### 2）Compose 启动

```powershell
docker compose up -d --build
docker compose logs -f
```

### 3）健康检查

```powershell
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/v1/models
```

### 4）停止服务

```powershell
docker compose down
```

## 模型目录结构

宿主机默认模型目录是 `D:/models`，会挂载到容器 `/models`。

```text
D:/models/
  translategemma-12b-it-MP-GGUF/
    translategemma-12b-it.Q4_K_H.gguf
    translategemma-12b-it.mmproj.gguf
```

`MODEL_NAME` 必须对应 `/models` 下的子目录名。

## 手动构建与运行

### 构建

```powershell
docker build -f MainstreamCudaDockerfile -t gemma-translate:mainstream-cuda .
```

### 运行

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

## 客户端请求示例

请求格式要点：
- 语言参数放在 `chat_template_kwargs`
- 文本可直接使用 `messages[].content` 字符串
- 图片使用 OpenAI 风格 `image_url`

### cURL（文本）

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

### cURL（图片）

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

### Python（requests）

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

## 配置说明

### Compose 变量

- `MODEL_ROOT`（默认：`D:/models`）
- `MODEL_NAME`（默认：`translategemma-12b-it-MP-GGUF`）
- `LLAMA_CPP_REF`（默认：`refs/pull/19052/head`）
- `LLAMA_N_GPU_LAYERS`（compose 默认 `-1`）
- `LLAMA_N_PARALLEL`（compose 默认 `2`）
- `LLAMA_N_CTX`（compose 默认 `3072`）

### 运行时变量

- `MODEL_NAME`（必填）
- `LLAMA_N_GPU_LAYERS`（默认 `0`）
- `LLAMA_N_CTX`（默认 `2048`）
- `LLAMA_N_PARALLEL`（默认 `4`）
- `LLAMA_N_THREADS`（可选）
- `LLAMA_FLASH_ATTN`（默认 `on`）
- `LLAMA_PORT`（默认 `8080`）
- `LLAMA_EXTRA_ARGS`（可选）

## GitHub CI/CD

本项目已内置 GitHub Actions：

- `.github/workflows/ci.yml`
  - 校验 `compose.yaml`
  - 构建 CPU 镜像做冒烟检查
- `.github/workflows/build-and-push-ghcr.yml`
  - 构建并推送镜像到 GHCR
  - 支持 `mainstream / legacy / future / cpu / all`
  - 支持自定义 `LLAMA_CPP_REF`（默认 `refs/pull/19052/head`）
  - `main`/tag 自动触发时仅构建 `mainstream`（节省 CI 成本）

### 使用方式

1. 把项目推送到你的 GitHub 仓库。
2. 打开 `Actions` -> `Build And Push GHCR` -> `Run workflow`。
3. 选择 `variant`（建议 `mainstream`），`push=true`。
4. 构建完成后从以下地址拉取：
   - `ghcr.io/<你的用户名或组织>/translategemma-llama-server:<tag>`

### 拉取与运行示例

```bash
docker pull ghcr.io/<你的用户名或组织>/translategemma-llama-server:mainstream-latest
docker run --gpus all -d \
  -p 127.0.0.1:8080:8080 \
  -v D:/models:/models \
  -e MODEL_NAME=translategemma-12b-it-MP-GGUF \
  ghcr.io/<你的用户名或组织>/translategemma-llama-server:mainstream-latest
```

如果你要长期稳定构建 CUDA 镜像，建议使用 self-hosted runner。

## 3080Ti-12G 调优建议

若显存不足：
1. 先降 `LLAMA_N_CTX`（如 `2048`）
2. 再降 `LLAMA_N_GPU_LAYERS`（如 `40`）
3. 再把 `LLAMA_N_PARALLEL` 从 `2` 调到 `1`

## 项目文件

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

## 说明

- 本项目默认使用包含 PR #19052 修复的 llama.cpp 引用：
  https://github.com/ggml-org/llama.cpp/pull/19052
- English README: `README.md`
