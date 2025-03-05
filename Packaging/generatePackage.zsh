#!/bin/zsh
set -e  # Beende das Skript bei Fehlern

# 🌍 Lade Umgebungsvariablen aus der `.env`-Datei
if [[ -f ".env" ]]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "❌ Fehler: .env-Datei fehlt! Bitte erstelle eine und definiere die Variablen."
    exit 1
fi

# 🛠 Variablen aus der `.env`
DAEMON_NAME="ACCpromAdapterDaemon"
IDENTIFIER="de.cstrube.ACCpromAdapterDaemon"
VERSION="1.0"

# Zertifikate & Notarisierung
DEV_ID_APP="${DEV_ID_APP:-MISSING}"
DEV_ID_INSTALLER="${DEV_ID_INSTALLER:-MISSING}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-MISSING}"

if [[ "$DEV_ID_APP" == "MISSING" || "$DEV_ID_INSTALLER" == "MISSING" || "$KEYCHAIN_PROFILE" == "MISSING" ]]; then
    echo "❌ Fehler: Eine oder mehrere Signatur-Variablen fehlen in .env!"
    exit 1
fi

# Installationspfade
BIN_INSTALL_LOCATION="/usr/local/bin"
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

# 🔏 Signiere das Binärprogramm mit Entitlements
ENTITLEMENTS_FILE="entitlements.plist"
if [[ -f "$ENTITLEMENTS_FILE" ]]; then
    echo "🔐 Entitlements-Datei gefunden: Signiere mit Entitlements..."
    codesign --deep --force --verify --verbose --timestamp --options runtime \
             --entitlements "$ENTITLEMENTS_FILE" \
             --sign "$DEV_ID_APP" "$STAGING_DIRECTORY/${BIN_INSTALL_LOCATION}/${DAEMON_NAME}"
else
    echo "⚠️ Keine Entitlements gefunden! Signiere ohne Entitlements..."
    codesign --deep --force --verify --verbose --timestamp --options runtime \
             --sign "$DEV_ID_APP" "$STAGING_DIRECTORY/${BIN_INSTALL_LOCATION}/${DAEMON_NAME}"
fi

# Zielverzeichnis für das Paket
PKG_OUTPUT_DIR="${BUILD_DIR}"
PKG_OUTPUT_PATH="${PKG_OUTPUT_DIR}/${DAEMON_NAME}.pkg"

# Sicherstellen, dass das Zielverzeichnis existiert
mkdir -p "$PKG_OUTPUT_DIR"

# 📦 Erstelle das Installationspaket mit `pkgbuild`
echo "📦 Erstelle Installationspaket: $PKG_OUTPUT_PATH"
pkgbuild --root "$STAGING_DIRECTORY" \
         --identifier "$IDENTIFIER" \
         --version "$VERSION" \
         --sign "$DEV_ID_INSTALLER" \
         "$PKG_OUTPUT_PATH" --verbose

echo "✅ Installationspaket erfolgreich erstellt: $PKG_OUTPUT_PATH"

# 🔏 Notarisierung des Pakets
echo "📝 Sende Paket zur Notarisierung..."
xcrun notarytool submit "$PKG_OUTPUT_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "📌 Notarisierung erfolgreich! Füge Staple hinzu..."
xcrun stapler staple "$PKG_OUTPUT_PATH"

echo "✅ Paket ist vollständig signiert, notarisiert und bereit für den Release: $PKG_OUTPUT_PATH"
