
#!/bin/sh
set -e

PLIST_PATH="/Library/LaunchDaemons/de.cstrube.ACCpromAdapterDaemon.plist"

echo "🚀 Lade und starte den ACCpromAdapterDaemon..."

# Lade den Daemon
sudo launchctl load "$PLIST_PATH"
sudo launchctl start de.cstrube.ACCpromAdapterDaemon

echo "✅ ACCpromAdapterDaemon wurde erfolgreich gestartet!"
