#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME="${MODEL_NAME:?ERROR: MODEL_NAME is required}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
N_GPU_LAYERS="${LLAMA_N_GPU_LAYERS:-0}"
N_CTX="${LLAMA_N_CTX:-2048}"
N_PARALLEL="${LLAMA_N_PARALLEL:-4}"
N_THREADS="${LLAMA_N_THREADS:-}"
FLASH_ATTN="${LLAMA_FLASH_ATTN:-on}"
USE_JINJA="${LLAMA_USE_JINJA:-off}"
CHAT_TEMPLATE="${LLAMA_CHAT_TEMPLATE:-}"
EXTRA_ARGS="${LLAMA_EXTRA_ARGS:-}"

case "${FLASH_ATTN,,}" in
    1|true|yes)
        FLASH_ATTN="on"
        ;;
    0|false|no)
        FLASH_ATTN="off"
        ;;
    on|off|auto)
        FLASH_ATTN="${FLASH_ATTN,,}"
        ;;
    *)
        echo "ERROR: LLAMA_FLASH_ATTN must be one of: on, off, auto"
        exit 1
        ;;
esac

case "${USE_JINJA,,}" in
    1|true|yes|on)
        USE_JINJA="on"
        ;;
    0|false|no|off)
        USE_JINJA="off"
        ;;
    *)
        echo "ERROR: LLAMA_USE_JINJA must be one of: on, off"
        exit 1
        ;;
esac

if ! command -v llama-server >/dev/null 2>&1; then
    echo "ERROR: llama-server binary not found in PATH"
    exit 1
fi

MODEL_DIR="/models/${MODEL_NAME}"
if [[ ! -d "${MODEL_DIR}" ]]; then
    echo "ERROR: model directory not found: ${MODEL_DIR}"
    echo "Available model folders in /models:"
    ls -1 /models/ 2>/dev/null || echo "  (none)"
    exit 1
fi

MODEL_PATH="$(find "${MODEL_DIR}" -type f -name "*.gguf" ! -iname "*mmproj*" | sort | head -n 1)"
if [[ -z "${MODEL_PATH}" ]]; then
    echo "ERROR: no model .gguf found in ${MODEL_DIR}"
    exit 1
fi

MMPROJ_PATH="$(find "${MODEL_DIR}" -type f -name "*mmproj*.gguf" | sort | head -n 1 || true)"

echo "============================================"
echo "Model name   : ${MODEL_NAME}"
echo "Model file   : ${MODEL_PATH}"
if [[ -n "${MMPROJ_PATH}" ]]; then
    echo "mmproj file  : ${MMPROJ_PATH} (image translation enabled)"
else
    echo "mmproj file  : not found (text-only mode)"
fi
echo "GPU layers   : ${N_GPU_LAYERS}"
echo "Parallel slot: ${N_PARALLEL}"
echo "Context size : ${N_CTX}"
echo "FlashAttn    : ${FLASH_ATTN}"
echo "Use Jinja    : ${USE_JINJA}"
if [[ -n "${CHAT_TEMPLATE}" ]]; then
    echo "Chat tmpl    : ${CHAT_TEMPLATE}"
fi
echo "Port         : ${LLAMA_PORT}"
if [[ -n "${EXTRA_ARGS}" ]]; then
    echo "Extra args   : ${EXTRA_ARGS}"
fi
echo "============================================"

ARGS=(
    -m "${MODEL_PATH}"
    --host 0.0.0.0
    --port "${LLAMA_PORT}"
    -c "${N_CTX}"
    -ngl "${N_GPU_LAYERS}"
    --parallel "${N_PARALLEL}"
    --cont-batching
    --metrics
)

if [[ "${USE_JINJA}" == "on" ]]; then
    ARGS+=(--jinja)
else
    ARGS+=(--no-jinja)
fi

if [[ -n "${CHAT_TEMPLATE}" ]]; then
    ARGS+=(--chat-template "${CHAT_TEMPLATE}")
fi

if [[ -n "${MMPROJ_PATH}" ]]; then
    ARGS+=(--mmproj "${MMPROJ_PATH}")
fi

if [[ -n "${FLASH_ATTN}" ]]; then
    ARGS+=(--flash-attn "${FLASH_ATTN}")
fi

if [[ -n "${N_THREADS}" ]]; then
    ARGS+=(-t "${N_THREADS}")
fi

if [[ -n "${EXTRA_ARGS}" ]]; then
    # shellcheck disable=SC2206
    EXTRA_ARGS_ARR=(${EXTRA_ARGS})
    ARGS+=("${EXTRA_ARGS_ARR[@]}")
fi

exec llama-server "${ARGS[@]}"
