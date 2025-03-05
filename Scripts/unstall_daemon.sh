#!/bin/zsh
set -e

echo "🛑 Entferne ACCpromAdapterDaemon..."

# Beende und entferne den Daemon
sudo launchctl unload /Library/LaunchDaemons/de.cstrube.ACCpromAdapterDaemon.plist
sudo rm /Library/LaunchDaemons/de.cstrube.ACCpromAdapterDaemon.plist

# Entferne die Binärdatei
sudo rm /usr/local/bin/ACCpromAdapterDaemon

echo "✅ ACCpromAdapterDaemon wurde vollständig entfernt!"
