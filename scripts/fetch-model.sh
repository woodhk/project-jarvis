#!/bin/bash
# Downloads the Whisper speech model (about 480 MB) to ~/Library/Application Support/Jarvis/models, unless it is there.
# Usage: scripts/fetch-model.sh [model]     model defaults to small.en; large-v3-turbo-q5_0 is the more accurate, slower one.
set -euo pipefail

MODEL="${1:-small.en}"
DIR="${JARVIS_HOME:-$HOME}/Library/Application Support/Jarvis/models"
FILE="$DIR/ggml-$MODEL.bin"
URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL.bin"
SMALL_EN_SHA1="db8a495a91d927739e50b3fc1cc4c6b8f6c2d022"

mkdir -p "$DIR"
if [ ! -f "$FILE" ]; then
  echo "Downloading $URL"
  curl -L --fail --progress-bar -o "$FILE.part" "$URL"
  mv "$FILE.part" "$FILE"
fi
if [ "$MODEL" = "small.en" ]; then
  if [ "$(shasum "$FILE" | cut -d' ' -f1)" != "$SMALL_EN_SHA1" ]; then
    echo "The file $FILE does not match the expected checksum. Delete it and run this again." >&2
    exit 1
  fi
fi
echo "Model ready: $FILE"
