#!/bin/bash
# Builds Jarvis, puts it in ~/Applications, and makes it start when you log in.
# To undo:  launchctl bootout gui/$(id -u)/local.jarvis.switcher
#           rm ~/Library/LaunchAgents/local.jarvis.switcher.plist && rm -r ~/Applications/Jarvis.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$HOME/Applications/Jarvis.app"
AGENT="$HOME/Library/LaunchAgents/local.jarvis.switcher.plist"
DOMAIN="gui/$(id -u)"

scripts/make-app.sh
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$APP"
ditto build/Jarvis.app "$APP"

sed "s|__APP__|$APP|" Resources/local.jarvis.switcher.plist > "$AGENT"
plutil -lint "$AGENT" > /dev/null
launchctl bootout "$DOMAIN/local.jarvis.switcher" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$AGENT"
echo "Installed $APP. It is running now and will start at every login."
