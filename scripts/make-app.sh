#!/bin/bash
# Builds build/Jarvis.app and signs it. Stops a running Jarvis first, because its program file is replaced.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Jarvis Local Signing"
APP="build/Jarvis.app"

swift build -c release
pkill -x Jarvis 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Jarvis "$APP/Contents/MacOS/Jarvis"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  codesign --force --sign "$NAME" "$APP"
else
  codesign --force --sign - "$APP"
  echo "WARNING: ad-hoc signature. macOS will ask for permissions again after every rebuild. Run scripts/make-cert.sh once to avoid this."
fi
echo "Built $APP"
