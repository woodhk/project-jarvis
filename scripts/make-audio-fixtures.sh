#!/bin/bash
# Makes the spoken test clips with a macOS voice. They are committed, so this only needs running to change them.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="Tests/JarvisKitTests/Fixtures"
mkdir -p "$OUT"
make_clip() { say -v Karen -r 185 --data-format=LEI16@16000 -o "$OUT/$1.wav" "$2"; }
make_clip open-youtube "open YouTube"
make_clip open-chatgpt "open ChatGPT"
make_clip open-source-insta "open the open source insta to comment session"
ls -l "$OUT"
