# llama-server 迁移方案

## 一、当前问题分析

### 1.1 GPU 空泡（idle bubbles）问题

当前架构使用 `llama-cpp-python` 在 Python 进程内调用模型推理，中间有一层 FastAPI 做请求转发。整个推理流程如下：

```
请求到达 -> 获取信号量 -> 卸载旧模型 -> 加载/获取模型 -> 构建参数 -> GPU推理 -> 提取结果 -> 释放信号量
           |<--------------------------  信号量占用期间  --------------------------->|
           |   CPU工作, GPU空闲   |  CPU工作  |   CPU工作   | 唯一用GPU |  CPU工作  |
```

**GPU 实际工作时间只占整个信号量持有时间的一小部分**，其余时间 GPU 完全空闲。

### 1.2 具体瓶颈

| 问题 | 位置 | 影响 |
|------|------|------|
| 信号量粒度过粗 | `llama_service.py:260` | CPU 准备工作期间也占用推理槽位，GPU 空等 |
| 默认并发度=1 | `llama_service.py:81-86` | 严格串行，请求之间必有 GPU 空闲窗口 |
| 缺少 GPU 优化参数 | `llama_service.py:200-205` | 未配置 `n_batch`、`flash_attn` 等关键参数 |
| 无批处理能力 | 架构层面 | 每个请求独立推理，无法合并多请求批处理 |
| Python GIL 限制 | 架构层面 | 同步阻塞调用受 Python 全局解释器锁影响 |
| FastAPI 层多余 | 架构层面 | 面向自有应用，中间网关增加延迟无实际价值 |
| 不支持图片翻译 | 功能层面 | 无多模态支持，TranslateGemma 的图片翻译能力被浪费 |

---

## 二、迁移方案概述

### 2.1 架构变更

```
迁移前:  客户端 -> FastAPI (Python) -> llama-cpp-python (进程内推理, 受GIL限制) -> GPU
                   端口 8080            同一进程, 仅支持文字翻译

迁移后:  客户端 -> llama-server (C++ 原生HTTP服务, --jinja --mmproj) -> GPU
                   端口 8080, 同时支持文字翻译和图片翻译
```

- **去掉 FastAPI 和全部 Python 代码**。容器里只运行一个进程：`llama-server`
- `llama-server` 是 llama.cpp 项目内置的 C++ 高性能 HTTP 推理服务器
- 使用 `--jinja` 模式启用 Jinja2 模板引擎，支持 TranslateGemma 的原生消息格式
- 使用 `--mmproj` 加载多模态投影器，支持图片翻译
- 客户端直接使用 `/v1/chat/completions` 端点，无需手动拼 prompt

### 2.2 为什么选择 llama-server 直连

| 特性 | 当前（FastAPI + llama-cpp-python） | 迁移后（llama-server 直连） |
|------|----------------------------------|---------------------------|
| 进程数 | 1个 Python 进程（含推理） | 1个 C++ 进程 |
| 并行推理 | Python 信号量，默认1 | 原生 `--parallel N` 多槽位 |
| 连续批处理 | 不支持 | 内置 `--cont-batching` |
| Flash Attention | 需手动配置 | 内置 `--flash-attn` |
| GPU 调度 | Python 层控制，受 GIL 限制 | C++ 原生调度，无 GIL |
| KV Cache 管理 | 基础 | 优化的多槽位 KV 缓存共享 |
| 图片翻译 | 不支持 | 原生支持（`--mmproj`） |
| 监控指标 | 无 | 内置 Prometheus `/metrics` |
| 网络转发 | 客户端 -> FastAPI -> 推理 | 客户端 -> 推理（少一跳） |
| 维护成本 | Python 代码 + Dockerfile | 仅 Dockerfile + entrypoint.sh |

### 2.3 关键技术点：`--jinja` 模式

默认情况下，llama-server 使用 C++ 消息解析器处理 `/v1/chat/completions` 请求，会**丢弃** TranslateGemma 的自定义字段（`source_lang_code`、`target_lang_code`、`url`）。

开启 `--jinja` 后，llama-server 直接把原始消息 JSON 传给模型内嵌的 Jinja2 模板处理，**所有自定义字段完整保留**。TranslateGemma 的模板能正确处理文字翻译和图片翻译两种内容类型。

> **注意：** `--jinja` 模式在早期版本中存在模板验证过严的问题（[issue #18895](https://github.com/ggml-org/llama.cpp/issues/18895)），已被 [PR #19019](https://github.com/ggml-org/llama.cpp/pull/19019) 修复。需要使用包含此修复的 llama.cpp 版本。

---

## 三、客户端适配指南

### 3.1 统一 API 端点

迁移后，**文字翻译和图片翻译使用同一个端点**：

```
POST http://server:8080/v1/chat/completions
```

区别仅在于消息内容中的 `type` 字段：`"text"` 或 `"image"`。

### 3.2 文字翻译

**原来的调用方式（FastAPI）：**
```json
POST http://server:8080/translate
{
    "model": "translategemma-4b-it-Q8_0",
    "source_lang_code": "en",
    "target_lang_code": "zh",
    "text": "Hello world",
    "max_new_tokens": 200,
    "temperature": 0.7
}
```

**迁移后的调用方式（llama-server）：**
```json
POST http://server:8080/v1/chat/completions
{
    "messages": [
        {
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "source_lang_code": "en",
                    "target_lang_code": "zh",
                    "text": "Hello world"
                }
            ]
        }
    ],
    "max_tokens": 200,
    "temperature": 0.7
}
```

**响应格式（OpenAI 兼容）：**
```json
{
    "choices": [
        {
            "message": {
                "role": "assistant",
                "content": "你好世界"
            },
            "finish_reason": "stop"
        }
    ],
    "usage": {
        "prompt_tokens": 25,
        "completion_tokens": 4,
        "total_tokens": 29
    }
}
```

### 3.3 图片翻译（新增能力）

```json
POST http://server:8080/v1/chat/completions
{
    "messages": [
        {
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source_lang_code": "en",
                    "target_lang_code": "zh",
                    "url": "data:image/png;base64,iVBORw0KGgo..."
                }
            ]
        }
    ],
    "max_tokens": 500
}
```

**图片传递方式：**
- Base64 内联：`"url": "data:image/png;base64,{base64编码}"`
- 本地路径（容器内）：`"url": "file:///path/to/image.png"`

**适用场景：**
- 翻译街道标牌、餐厅菜单、产品标签
- 翻译扫描文档中的文字
- 翻译截图中的 UI 文字

**图片翻译建议：**
- 使用高对比度、文字清晰的图片
- 尽量裁剪到只包含需要翻译的文字区域
- 每张图片最好只包含单一文字段落，输出质量更好

### 3.4 消息格式汇总

TranslateGemma 的消息内容只支持一个 content 项，格式如下：

| 字段 | 文字翻译 | 图片翻译 |
|------|---------|---------|
| `type` | `"text"` | `"image"` |
| `source_lang_code` | 源语言代码（如 `"en"`） | 源语言代码 |
| `target_lang_code` | 目标语言代码（如 `"zh"`） | 目标语言代码 |
| `text` | 待翻译文本 | 不需要 |
| `url` | 不需要 | 图片 URL 或 base64 |

语言代码支持 ISO 639-1 格式（如 `en`、`zh`）和区域化格式（如 `en-US`、`zh-CN`）。

### 3.5 可用的采样参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `max_tokens` | int | 最大生成 token 数（对应原来的 `max_new_tokens`） |
| `temperature` | float | 温度参数 |
| `top_p` | float | Top-P 采样 |
| `top_k` | int | Top-K 采样 |
| `min_p` | float | Min-P 采样 |
| `repeat_penalty` | float | 重复惩罚 |
| `presence_penalty` | float | 存在惩罚 |
| `frequency_penalty` | float | 频率惩罚 |

### 3.6 可用的 API 端点

| 端点 | 说明 |
|------|------|
| `POST /v1/chat/completions` | 翻译主端点（文字 + 图片，推荐） |
| `POST /v1/completions` | 原始文本补全（手动拼 prompt 时使用） |
| `GET /health` | 健康检查，返回 `{"status": "ok"}` |
| `GET /v1/models` | 返回已加载的模型信息 |
| `GET /metrics` | Prometheus 格式监控指标 |
| `POST /tokenize` | 文本分词 |
| `POST /detokenize` | token 转文本 |

### 3.7 备选：手动拼 prompt 方式

如果不使用 `--jinja` 模式，也可以通过 `/v1/completions` 手动构建 prompt：

```
<start_of_turn>user
You are a professional {源语言名} ({源语言代码}) to {目标语言名} ({目标语言代码}) translator. Your goal is to accurately convey the meaning and nuances of the original {源语言名} text while adhering to {目标语言名} grammar, vocabulary, and cultural sensitivities.
Produce only the {目标语言名} translation, without any additional explanations or commentary. Please translate the following {源语言名} text into {目标语言名}:


{待翻译文本}<end_of_turn>
<start_of_turn>model
```

此方式仅支持文字翻译，不支持图片翻译。

---

## 四、模型文件要求

### 4.1 文字翻译（基础）

仅需模型 GGUF 文件，现有模型文件即可直接使用：

```
models/translategemma-4b-it-Q8_0/
  translategemma-4b-it-Q8_0.gguf
```

### 4.2 图片翻译（需额外 mmproj 文件）

图片翻译需要多模态投影器（mmproj）文件，用于将图片通过 SigLIP 视觉编码器转换为模型可理解的 embedding。

**模型目录结构：**
```
models/translategemma-12b-it-Hybrid/
  translategemma-12b-it-Hybrid.gguf       # 模型文件
  translategemma-12b-it.mmproj-Q8_0.gguf  # 多模态投影器
```

**mmproj 文件来源：**
- [steampunque/translategemma-12b-it-Hybrid-GGUF](https://huggingface.co/steampunque/translategemma-12b-it-Hybrid-GGUF) -- 包含 12B 模型 + mmproj

**下载示例：**
```bash
# 下载带 mmproj 的 12B 模型
hf download steampunque/translategemma-12b-it-Hybrid-GGUF \
  --local-dir models/translategemma-12b-it-Hybrid
```

> **注意：** 不需要 mmproj 文件也能运行，只是不支持图片翻译功能。entrypoint.sh 会自动检测是否存在 mmproj 文件并据此启用图片支持。

---

## 五、服务端变更

### 5.1 删除的文件/内容

迁移后以下文件不再需要包含在 Docker 镜像中：

| 文件 | 原用途 | 处理方式 |
|------|-------|---------|
| `app/main.py` | FastAPI 端点定义 | 从镜像中移除 |
| `app/lib/llama_service.py` | Python 推理封装 | 从镜像中移除 |
| `app/lib/model_registry.py` | 模型文件扫描 | 从镜像中移除 |
| `app/lib/locales.py` | 语言代码列表 | 移到客户端做校验 |
| `requirements.txt` | Python 依赖 | 不再需要（无 Python） |

这些文件保留在 Git 仓库中供参考，但不再 COPY 进 Docker 镜像。

### 5.2 `entrypoint.sh` -- 新文件

容器唯一的启动脚本，直接运行 llama-server：

```bash
#!/bin/bash
set -euo pipefail

# ---- 配置 ----
MODEL_NAME="${MODEL_NAME:?ERROR: MODEL_NAME 环境变量必须设置}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
N_GPU_LAYERS="${LLAMA_N_GPU_LAYERS:-0}"
N_CTX="${LLAMA_N_CTX:-2048}"
N_PARALLEL="${LLAMA_N_PARALLEL:-4}"
N_THREADS="${LLAMA_N_THREADS:-}"
FLASH_ATTN="${LLAMA_FLASH_ATTN:-on}"

# ---- 查找模型文件 ----
MODEL_DIR="/models/${MODEL_NAME}"
if [ ! -d "$MODEL_DIR" ]; then
    echo "ERROR: model directory not found: $MODEL_DIR"
    echo "Available models:"
    ls -1 /models/ 2>/dev/null || echo "  (none)"
    exit 1
fi

MODEL_PATH=$(find "$MODEL_DIR" -name "*.gguf" ! -name "*mmproj*" -type f | head -1)
if [ -z "$MODEL_PATH" ]; then
    echo "ERROR: no .gguf model file found in $MODEL_DIR"
    exit 1
fi

# ---- 检测 mmproj 文件（图片翻译支持）----
MMPROJ_PATH=$(find "$MODEL_DIR" -name "*mmproj*" -type f | head -1)

echo "============================================"
echo "  Model:      $MODEL_NAME"
echo "  File:       $MODEL_PATH"
if [ -n "$MMPROJ_PATH" ]; then
    echo "  mmproj:     $MMPROJ_PATH (image translation enabled)"
else
    echo "  mmproj:     (not found, text-only mode)"
fi
echo "  GPU layers: $N_GPU_LAYERS"
echo "  Parallel:   $N_PARALLEL"
echo "  Context:    $N_CTX"
echo "  Port:       $LLAMA_PORT"
echo "============================================"

# ---- 构建启动参数 ----
ARGS=(
    -m "$MODEL_PATH"
    --host 0.0.0.0
    --port "$LLAMA_PORT"
    -c "$N_CTX"
    -ngl "$N_GPU_LAYERS"
    --parallel "$N_PARALLEL"
    --cont-batching
    --jinja
    --metrics
)

# 如有 mmproj 文件，启用图片翻译
if [ -n "$MMPROJ_PATH" ]; then
    ARGS+=(--mmproj "$MMPROJ_PATH")
fi

if [ "$FLASH_ATTN" = "on" ]; then
    ARGS+=(--flash-attn)
fi

if [ -n "$N_THREADS" ]; then
    ARGS+=(-t "$N_THREADS")
fi

# ---- 启动 llama-server（前台运行）----
exec llama-server "${ARGS[@]}"
```

**设计要点：**
- llama-server 直接前台运行（`exec`），Docker 的 SIGTERM 直接传达
- 自动检测 mmproj 文件：有则启用图片翻译，无则仅文字翻译
- 查找模型文件时排除 mmproj 文件（`! -name "*mmproj*"`）
- `--jinja` 模式始终开启，让 TranslateGemma 的原生模板处理消息

### 5.3 所有 Dockerfile（共4个） -- 大幅简化

**核心变更：**
- 移除所有 Python 相关内容（pip install、Python 依赖、app/ 代码）
- 仅构建 llama-server 二进制 + 复制 entrypoint.sh
- 需使用包含 PR #19019 修复的 llama.cpp 版本

**MainstreamCudaDockerfile 示例：**

```dockerfile
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

# 安装构建依赖
RUN apt-get update && apt-get install -y \
    cmake git build-essential curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 从源码构建 llama-server（固定到包含 PR #19019 修复的版本）
ARG LLAMA_CPP_VERSION=b5040
RUN git clone --depth 1 --branch ${LLAMA_CPP_VERSION} \
        https://github.com/ggml-org/llama.cpp.git /tmp/llama.cpp \
    && cmake -B /tmp/llama.cpp/build -S /tmp/llama.cpp \
       -DCMAKE_BUILD_TYPE=Release \
       -DGGML_CUDA=ON \
       -DCMAKE_CUDA_ARCHITECTURES="75;80;86;89" \
       -DGGML_CUDA_FA_ALL_QUANTS=ON \
    && cmake --build /tmp/llama.cpp/build --config Release -t llama-server -j$(nproc) \
    && cp /tmp/llama.cpp/build/bin/llama-server /usr/local/bin/ \
    && rm -rf /tmp/llama.cpp

# 复制启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
```

**各 Dockerfile 差异：**

| Dockerfile | 基础镜像 | CUDA 架构 | 特殊说明 |
|---|---|---|---|
| Dockerfile (CPU) | ubuntu:22.04 | 无 CUDA 标志 | 仅 `-DGGML_NATIVE=OFF`，不支持图片翻译（缺乏算力） |
| MainstreamCuda | nvidia/cuda:12.4.0-devel | `75;80;86;89` | `GGML_CUDA_FA_ALL_QUANTS=ON` |
| LegacyCuda | nvidia/cuda:12.1.1-devel | `61` | 不加 FA_ALL_QUANTS，FLASH_ATTN=off |
| FutureCuda | pytorch:2.9.1-cuda13.0 | `89;90;100;120` | 需设置 `CUDACXX` 路径指向 CUDA 13.0 |

---

## 六、环境变量

| 变量名 | 默认值 | 说明 |
|---|---|---|
| `MODEL_NAME` | （必填） | 模型目录名，如 `translategemma-12b-it-Hybrid` |
| `LLAMA_N_GPU_LAYERS` | `0` | GPU 层数（`-1` = 全部卸载到 GPU） |
| `LLAMA_N_CTX` | `2048` | 上下文窗口大小 |
| `LLAMA_N_PARALLEL` | `4` | 并行推理槽位数 |
| `LLAMA_N_THREADS` | 自动 | CPU 线程数 |
| `LLAMA_FLASH_ATTN` | `on` | Flash Attention 开关（Pascal 需设为 `off`） |
| `LLAMA_PORT` | `8080` | 服务端口 |

**不再需要的环境变量：**
- `LLAMA_MAX_CONCURRENT_INFERENCES` -- 被 `LLAMA_N_PARALLEL` 替代
- `LLAMA_INFERENCE_ACQUIRE_TIMEOUT_SECONDS` -- llama-server 内部管理队列
- `LLAMA_MAX_GPU_LAYERS` -- 不再需要上限控制

---

## 七、docker run 用法

```bash
# GPU 部署（文字 + 图片翻译）
docker run --gpus all -d \
  -p 127.0.0.1:8080:8080 \
  -v /path/to/models:/models \
  -e MODEL_NAME=translategemma-12b-it-Hybrid \
  -e LLAMA_N_GPU_LAYERS=-1 \
  -e LLAMA_N_PARALLEL=4 \
  gemma-translate:mainstream-cuda

# GPU 部署（仅文字翻译，使用不带 mmproj 的模型）
docker run --gpus all -d \
  -p 127.0.0.1:8080:8080 \
  -v /path/to/models:/models \
  -e MODEL_NAME=translategemma-4b-it-Q8_0 \
  -e LLAMA_N_GPU_LAYERS=-1 \
  gemma-translate:mainstream-cuda

# CPU 部署（仅文字翻译）
docker run -d \
  -p 127.0.0.1:8080:8080 \
  -v /path/to/models:/models \
  -e MODEL_NAME=translategemma-4b-it-Q8_0 \
  gemma-translate:cpu
```

---

## 八、实施步骤

| 步骤 | 内容 | 说明 |
|------|------|------|
| 1 | 创建 `entrypoint.sh` | 容器启动脚本（含 mmproj 自动检测） |
| 2 | 重写 `MainstreamCudaDockerfile` | 主要测试目标 |
| 3 | 重写其余 3 个 Dockerfile | CPU / Legacy / Future |
| 4 | 更新 `README.md` | 新的 API 说明、图片翻译用法、docker run 示例 |

总共只需要改 **6 个文件**（1 个新建 + 4 个 Dockerfile 重写 + 1 个文档更新），不再需要修改任何 Python 代码。

---

## 九、验证清单

### 基础验证
1. 构建 MainstreamCudaDockerfile 镜像
2. 使用小模型（translategemma-4b-it-Q8_0）启动容器
3. 验证 `GET /health` 返回 `{"status": "ok"}`
4. 验证 `GET /v1/models` 返回模型信息

### 文字翻译验证
5. 使用 `/v1/chat/completions` + `type: "text"` 验证文字翻译正确

### 图片翻译验证
6. 使用带 mmproj 的模型重新启动容器
7. 使用 `/v1/chat/completions` + `type: "image"` 验证图片翻译正确

### 性能验证
8. 并发发送多个请求，确认并行槽位工作正常
9. 访问 `/metrics` 确认 GPU 槽位利用率

---

## 十、注意事项

1. **llama.cpp 版本要求：** 必须使用包含 [PR #19019](https://github.com/ggml-org/llama.cpp/pull/19019) 修复的版本（修复 `--jinja` 模式下 TranslateGemma 模板验证失败的问题）。Dockerfile 中通过 `ARG LLAMA_CPP_VERSION` 固定版本号。

2. **mmproj 文件可选：** 不提供 mmproj 文件时，服务仍可正常运行，仅文字翻译可用。entrypoint.sh 自动检测并按需启用。

3. **Pascal 显卡兼容性：** Pascal 架构（10xx 系列）不支持 Flash Attention。LegacyCudaDockerfile 中应默认设置 `LLAMA_FLASH_ATTN=off`。

4. **大模型加载时间：** 27B 模型加载到显存可能需要数分钟。llama-server 在模型加载完成前 `/health` 返回 503，加载完成后返回 200。客户端应据此判断服务是否就绪。

5. **并行槽位数调优：** `LLAMA_N_PARALLEL` 的最佳值取决于模型大小和显存容量：
   - 4B 模型：建议 4-8 个槽位
   - 12B 模型：建议 2-4 个槽位
   - 27B 模型：建议 1-2 个槽位

6. **图片翻译的上下文大小：** 图片会被视觉编码器转换为 token 序列（通常数百个 token）。如果同时处理图片翻译，建议将 `LLAMA_N_CTX` 适当增大（如 4096）。

7. **语言代码校验：** 原先由 FastAPI 做的语言代码校验需要移到客户端应用中。原始语言列表在 `app/lib/locales.py` 文件中。TranslateGemma 支持 55 种语言。

---

## 参考链接

- [TranslateGemma 官方博客](https://blog.google/innovation-and-ai/technology/developers-tools/translategemma/)
- [TranslateGemma 技术报告](https://arxiv.org/pdf/2601.09012)
- [google/translategemma-12b-it (HuggingFace)](https://huggingface.co/google/translategemma-12b-it)
- [steampunque/translategemma-12b-it-Hybrid-GGUF (含 mmproj)](https://huggingface.co/steampunque/translategemma-12b-it-Hybrid-GGUF)
- [llama.cpp 多模态文档](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md)
- [llama.cpp server 文档](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [issue #18895: 模板验证问题](https://github.com/ggml-org/llama.cpp/issues/18895)
- [PR #19019: 修复模板验证](https://github.com/ggml-org/llama.cpp/pull/19019)
