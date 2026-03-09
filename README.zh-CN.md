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

### 0）国内镜像地址

如果你在国内网络环境下使用 Docker，可以直接拉取阿里云个人版镜像仓库中的预构建镜像：

- 带模型版本：`crpi-ljf6ob20bt5kluhe.cn-shanghai.personal.cr.aliyuncs.com/boyqiuproxy/translategemma-llama-server:mainstream-latest-withmodel`
  - 说明：镜像内已经包含模型，可直接运行，不需要额外挂载宿主机模型目录。
- 不带模型版本：`crpi-ljf6ob20bt5kluhe.cn-shanghai.personal.cr.aliyuncs.com/boyqiuproxy/translategemma-llama-server:mainstream-latest`
  - 说明：镜像内不包含模型，需要自行准备模型文件并挂载到容器 `/models`。

示例：

```powershell
docker pull crpi-ljf6ob20bt5kluhe.cn-shanghai.personal.cr.aliyuncs.com/boyqiuproxy/translategemma-llama-server:mainstream-latest-withmodel
docker pull crpi-ljf6ob20bt5kluhe.cn-shanghai.personal.cr.aliyuncs.com/boyqiuproxy/translategemma-llama-server:mainstream-latest
```

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

## 构建自带模型的镜像

如果你已经先构建好了基础镜像（例如 `gemma-translate:mainstream-cuda`），并且仓库里的模型文件已经放在 `scripts/models/` 下，可以直接用 `BundledModelDockerfile` 再封一层，把模型一起打进镜像。

### 构建

```powershell
docker build -f BundledModelDockerfile `
  --build-arg BASE_IMAGE=gemma-translate:mainstream-cuda `
  -t gemma-translate:mainstream-cuda-bundled .
```

### 运行

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

这个镜像不再依赖宿主机 `-v D:/models:/models` 挂载；模型会直接位于容器内的 `/models/translategemma-12b-it-MP-GGUF/`。

## 构建参数详解（重点）

### `docker build` 命令参数

- `-f <Dockerfile>`：指定构建配方（如 `MainstreamCudaDockerfile`、`LegacyCudaDockerfile`、`FutureCudaDockerfile`、`Dockerfile`）
- `-t <image:tag>`：生成镜像名和标签
- `--build-arg KEY=VALUE`：传入 Dockerfile 的构建期参数
- `.`：构建上下文（当前目录）

示例：

```powershell
docker build -f MainstreamCudaDockerfile `
  -t gemma-translate:mainstream-cuda `
  --build-arg LLAMA_CPP_REF=master `
  --build-arg LLAMA_CUDA_ARCH=86 `
  .
```

### Dockerfile 中的构建参数（ARG）

- `LLAMA_CPP_REF`
  - 含义：指定要编译的 `llama.cpp` 源码引用（分支 / tag / commit / refspec）
  - 默认：`master`
  - 示例：`master`、`bXXXX`、`<commit_sha>`
- `LLAMA_CUDA_ARCH`（仅 CUDA 镜像）
  - 含义：传给 `-DCMAKE_CUDA_ARCHITECTURES` 的 CUDA 架构列表
  - 默认值：
    - `MainstreamCudaDockerfile`：`86`
    - `LegacyCudaDockerfile`：`61`
    - `FutureCudaDockerfile`：`89;90;100;120`

### `LLAMA_CUDA_ARCH` 每个数字是什么意思

这些数字对应 CUDA 的 **SM（计算能力）版本去掉小数点**：

- `61` -> sm_61（Pascal 时代常见，如 GTX 10xx 代）
- `75` -> sm_75（Turing，如 RTX 20xx / T4）
- `80` -> sm_80（Ampere 数据中心卡，如 A100）
- `86` -> sm_86（Ampere GA10x，如 RTX 30xx，含 3080 Ti）
- `89` -> sm_89（Ada，如 RTX 40xx）
- `90` -> sm_90（Hopper，如 H100/H200）
- `100` / `120` -> 更新一代架构预留值（只有你确实需要跨新老代兼容时再保留）

如何选：

- 只有单一目标显卡：只填一个值（编译最快、镜像更小）
- 3080Ti 用 `LLAMA_CUDA_ARCH=86`
- 要兼容多代显卡：用分号分隔，如 `86;89`（编译更慢、镜像更大）

### CUDA 构建里 CMake 参数解释

- `-DGGML_CUDA=ON`：开启 CUDA 后端
- `-DCMAKE_CUDA_ARCHITECTURES=...`：只编译指定架构的 CUDA 内核
- `-DGGML_CUDA_FA_ALL_QUANTS=ON`：开启更全的 Flash-Attn 量化 kernel 路径（运行更通用，编译更慢）
- `-DCMAKE_EXE_LINKER_FLAGS=...`：给链接器补 CUDA stub 路径，避免 CI 中 `libcuda.so.1 not found` 这类链接报错

## 客户端请求示例

请求格式要点：
- 文本翻译可继续使用 `chat_template_kwargs`
- 图片翻译当前要求 `messages[].content` 是仅包含 1 个元素的数组
- 该元素直接携带 `type`、`source_lang_code`、`target_lang_code`、`url`

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

### PowerShell（本地图片或图片 URL）

仓库里提供了一个可直接测试图片翻译的脚本：`scripts/test-image-translate.ps1`

本地图片示例：

```powershell
./scripts/test-image-translate.ps1 `
  -ImagePath "D:/test-images/menu-en.png" `
  -SourceLangCode en `
  -TargetLangCode zh
```

远程图片示例：

```powershell
./scripts/test-image-translate.ps1 `
  -ImageUrl "https://example.com/sample-sign.jpg" `
  -SourceLangCode auto `
  -TargetLangCode zh
```

常用参数：
- `-BaseUrl`：后端地址，默认 `http://127.0.0.1:8080`
- `-ImagePath`：本地图片路径，脚本会自动转成 data URL
- `-ImageUrl`：远程图片 URL
- `-SourceLangCode` / `-TargetLangCode`：源语言 / 目标语言
- `-RawResponse`：输出完整 JSON 响应，便于排查

## 配置说明

### Compose 变量

- `MODEL_ROOT`（默认：`./models`）：挂载到容器内的 `/models`；如果宿主机路径写错，启动时就找不到模型目录。
- `MODEL_NAME`（默认：`translategemma-12b-it-MP-GGUF`）：会传递给运行时，用来选择 `/models/<MODEL_NAME>`；同时也决定是否自动发现同目录下的 `*mmproj*.gguf`。
- `LLAMA_CPP_REF`（默认：`master`）：构建期使用的 `llama.cpp` 源码引用；修改它会触发镜像重编译，并可能改变支持的参数、行为和性能。
- `LLAMA_N_GPU_LAYERS`（compose 默认 `-1`）：compose 有意覆盖了入口脚本默认值 `0`；`-1` 表示尽量把全部层卸载到 GPU，通常更快，但显存占用最高。
- `LLAMA_N_PARALLEL`（compose 默认 `2`）：compose 有意覆盖了入口脚本默认值 `4`；把并发槽位降到 `2`，是为了在 12GB 显卡上减少 KV cache 占用。
- `LLAMA_N_CTX`（compose 默认 `3072`）：compose 有意覆盖了入口脚本默认值 `2048`；可支持更长上下文，但会预留更多内存。
- `LLAMA_FLASH_ATTN`（compose 默认 `on`）：在主流 CUDA 镜像里默认启用 Flash Attention；若运行环境支持，通常能改善速度或显存效率。
- `LLAMA_PORT`（compose 固定为 `8080`）：容器内部监听 `8080`，compose 也映射了 `127.0.0.1:8080:8080`；如果要改它，`ports` 和健康检查地址也要一起改。

### 运行时变量

- `MODEL_NAME`（必填）：启动时会定位 `/models/<MODEL_NAME>`。如果目录不存在，或目录下找不到非 `mmproj` 的 `.gguf` 主模型文件，容器会立即退出。如果同目录里找到了 `*mmproj*.gguf`，会自动开启图片翻译；否则就是纯文本模式。
- `LLAMA_N_GPU_LAYERS`（映射到 `-ngl`，默认 `0`）：控制多少层 Transformer 卸载到 GPU。`0` 表示纯 CPU，`-1` 表示尽量全部卸载到 GPU，正整数表示卸载指定层数。数值越大通常越快，但显存占用也越高，更容易 OOM。
- `LLAMA_N_CTX`（映射到 `-c`，默认 `2048`）：设置上下文窗口大小。值越大，可容纳的长提示词和历史越多，但即使没有请求也会预留更多 KV cache 内存；显存不足时通常先降这个参数。
- `LLAMA_N_PARALLEL`（映射到 `--parallel`，默认 `4`）：设置 `llama-server` 维护的并发解码槽位数量。这个镜像固定开启了 `--cont-batching`，所以把它调大可以提升并发和吞吐，但也会按槽位数量放大 KV cache 压力，压缩单请求可用内存空间。
- `LLAMA_N_THREADS`（映射到 `-t`，可选）：限制 CPU 侧工作线程数。适当增大可能降低延迟，但超过 CPU 合理范围后会出现线程争抢；如果不设置，则交给 `llama-server` 自行决定。
- `LLAMA_FLASH_ATTN`（映射到 `--flash-attn`，默认 `on`；但 `LegacyCudaDockerfile` 镜像默认是 `off`）：接受 `on`、`off`、`auto`，也接受 `1/0`、`true/false`、`yes/no` 这类别名。传入非法值时，入口脚本会直接报错退出。`on` 表示显式启用，`off` 表示禁用，`auto` 表示由 `llama-server` 自行判断。
- `LLAMA_PORT`（映射到 `--port`，默认 `8080`）：修改容器内服务监听端口。手动 `docker run` 时，宿主机的 `-p` 映射要同步修改；使用 compose 时，`ports` 和健康检查地址也要一起改。
- `LLAMA_EXTRA_ARGS`（可选）：会在启动 `llama-server` 时追加到内置参数之后，适合透传镜像没有单独暴露的高级参数。注意入口脚本是按空格切分它的，所以带空格的复杂引号写法并不稳妥；如果重复传了前面已经设置过的同名参数，后面的值是否覆盖前面的值取决于 `llama-server` 的解析方式。

## GitHub CI/CD

本项目已内置 GitHub Actions：

- `.github/workflows/ci.yml`
  - 校验 `compose.yaml`
  - 构建 CPU 镜像做冒烟检查
- `.github/workflows/build-and-push-ghcr.yml`
  - 构建并推送镜像到 GHCR
  - 支持 `mainstream / legacy / future / cpu / all`
  - 支持自定义 `LLAMA_CPP_REF`（默认 `master`）
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
BundledModelDockerfile
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
