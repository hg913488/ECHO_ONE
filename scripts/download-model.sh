#!/bin/bash
set -euo pipefail

MODEL_DIR="Resources/models"
MODEL_FILE="ggml-small.en.bin"
MODEL_PATH="${MODEL_DIR}/${MODEL_FILE}"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_FILE}"

if [ -f "${MODEL_PATH}" ]; then
    echo "Model already exists at ${MODEL_PATH}"
    exit 0
fi

mkdir -p "${MODEL_DIR}"
echo "Downloading ${MODEL_FILE} (~466 MB)..."
curl -L --progress-bar -o "${MODEL_PATH}" "${MODEL_URL}"
echo "Done. Model saved to ${MODEL_PATH}"
