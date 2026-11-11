#!/bin/bash
# Copies your TypeSafe API key from this shell (TYPESAFE_API_KEY) into the login Keychain, where Jarvis reads it.
# An app started at login does not see shell variables. The key is never printed.
# The Jarvis program stores it itself, so the Keychain lets Jarvis read it back without asking.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${TYPESAFE_API_KEY:-}" ]; then
  echo "TYPESAFE_API_KEY is not set in this shell. Nothing was stored." >&2
  exit 1
fi
BIN="build/Jarvis.app/Contents/MacOS/Jarvis"
[ -x "$BIN" ] || scripts/make-app.sh
"$BIN" --store-key
