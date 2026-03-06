#!/usr/bin/env bash
set -euo pipefail

# Download TranslateGemma model files on Linux.
#
# Prerequisites:
#   - huggingface-cli installed: pip install "huggingface_hub[cli]"
#   - authenticated: hf auth login
#
# Example:
#   bash scripts/linux-download-model.sh \
#     --model-root /opt/models \
#     --model-name translategemma-12b-it-MP-GGUF

MODEL_REPO="steampunque/translategemma-12b-it-MP-GGUF"
MODEL_NAME="translategemma-12b-it-MP-GGUF"
MODEL_ROOT="/opt/models"
QUANT_FILE="translategemma-12b-it.Q4_K_H.gguf"
MMPROJ_FILE="translategemma-12b-it.mmproj.gguf"

usage() {
  cat <<'EOF'
Usage:
  linux-download-model.sh [options]

Options:
  --model-root <path>      Host model root dir (default: /opt/models)
  --model-name <name>      Model folder name (default: translategemma-12b-it-MP-GGUF)
  --model-repo <repo>      HF repo (default: steampunque/translategemma-12b-it-MP-GGUF)
  --quant-file <file>      Quant gguf file
  --mmproj-file <file>     mmproj gguf file
  -h, --help               Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model-root) MODEL_ROOT="$2"; shift 2 ;;
    --model-name) MODEL_NAME="$2"; shift 2 ;;
    --model-repo) MODEL_REPO="$2"; shift 2 ;;
    --quant-file) QUANT_FILE="$2"; shift 2 ;;
    --mmproj-file) MMPROJ_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v hf >/dev/null 2>&1; then
  echo "ERROR: 'hf' not found. Install first: pip install \"huggingface_hub[cli]\"" >&2
  exit 1
fi

TARGET_DIR="${MODEL_ROOT}/${MODEL_NAME}"
mkdir -p "${TARGET_DIR}"

echo "Downloading model files to: ${TARGET_DIR}"
hf download "${MODEL_REPO}" "${QUANT_FILE}" "${MMPROJ_FILE}" --local-dir "${TARGET_DIR}"

echo "Done."
echo "Model directory: ${TARGET_DIR}"
