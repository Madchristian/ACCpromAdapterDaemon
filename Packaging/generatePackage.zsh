#!/bin/zsh
set -e  # Beende das Skript bei Fehlern

# Variablen anpassen
DAEMON_NAME="ACCpromAdapterDaemon"
IDENTIFIER="de.cstrube.ACCpromAdapterDaemon"
VERSION="1.0"

# Installationspfade
BIN_INSTALL_LOCATION="/usr/local/bin"  # Alternativ: /Library/Application Support/ACCpromAdapterDaemon
LAUNCHD_INSTALL_LOCATION="/Library/LaunchDaemons"

# Staging-Verzeichnis für die Paket-Erstellung
STAGING_DIRECTORY="${TMPDIR}/staging"
BUILD_DIR="${HOME}/Builds/ACCpromAdapterDaemon"

# Falls BUILT_PRODUCTS_DIR nicht existiert, explizit setzen
if [[ -z "$BUILT_PRODUCTS_DIR" ]]; then
    BUILT_PRODUCTS_DIR="${BUILD_DIR}/Build/Products/Release"
fi

# Sicherstellen, dass der Build existiert
if [[ ! -d "$BUILT_PRODUCTS_DIR" ]]; then
    echo "❌ Fehler: Build-Verzeichnis $BUILT_PRODUCTS_DIR existiert nicht!"
    exit 1
fi

echo "📦 Erstelle Staging-Verzeichnis: $STAGING_DIRECTORY"
rm -rf "$STAGING_DIRECTORY"
mkdir -p "$STAGING_DIRECTORY/${BIN_INSTALL_LOCATION}"
mkdir -p "$STAGING_DIRECTORY/${LAUNCHD_INSTALL_LOCATION}"

# Kopiere die Binärdatei und die LaunchDaemon-Konfig
echo "🚀 Kopiere Binärdatei nach Staging..."
cp "${BUILT_PRODUCTS_DIR}/${DAEMON_NAME}" "$STAGING_DIRECTORY/${BIN_INSTALL_LOCATION}/"

echo "⚙️  Kopiere LaunchDaemon .plist..."
cp "${BUILT_PRODUCTS_DIR}/Library/LaunchDaemons/de.cstrube.ACCpromAdapterDaemon.plist" "$STAGING_DIRECTORY/${LAUNCHD_INSTALL_LOCATION}/"

# Zielverzeichnis für das Paket
PKG_OUTPUT_DIR="${BUILD_DIR}"
PKG_OUTPUT_PATH="${PKG_OUTPUT_DIR}/${DAEMON_NAME}.pkg"

# Sicherstellen, dass das Zielverzeichnis existiert
mkdir -p "$PKG_OUTPUT_DIR"

# Erstelle das Installationspaket mit `pkgbuild`
echo "📦 Erstelle Installationspaket: $PKG_OUTPUT_PATH"
pkgbuild --root "$STAGING_DIRECTORY" \
         --identifier "$IDENTIFIER" \
         --version "$VERSION" \
         --sign "Developer ID Installer: Christian Strube (73SP5UXC3Q)" \
         "$PKG_OUTPUT_PATH" --debug
echo "✅ Installationspaket erfolgreich erstellt: $PKG_OUTPUT_PATH"
