#!/bin/bash
# Builds the Jarvis add-on for VS Code and installs it. Afterwards, run "Developer: Reload Window" in each VS Code
# window (or restart VS Code). To remove it: code --uninstall-extension local.jarvis-bridge
set -euo pipefail
cd "$(dirname "$0")/../vscode-addon"

npm ci --no-fund --no-audit
npm run build
npx vsce package --allow-missing-repository --skip-license --no-dependencies -o jarvis-bridge.vsix
code --install-extension jarvis-bridge.vsix --force
echo "Installed. Now run \"Developer: Reload Window\" in each VS Code window."
