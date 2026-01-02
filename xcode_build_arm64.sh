#!/bin/bash

# Xcode Build Script - ARM64 only

set -e

echo "==========================================="
echo "Xcode Build - ARM64 ONLY"
echo "==========================================="

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}[1/2] Clean Build Directory...${NC}"
xcodebuild clean \
    -scheme nethack \
    -configuration Debug \
    -quiet

echo -e "${YELLOW}[2/2] Baue Xcode Projekt (ARM64 Simulator)...${NC}"
echo -e "${YELLOW}Note: Xcode pre-build script handles dylib build automatically${NC}"
xcodebuild build \
    -scheme nethack \
    -configuration Debug \
    -sdk iphonesimulator \
    -arch arm64 \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS=arm64 \
    VALID_ARCHS=arm64 \
    EXCLUDED_ARCHS="x86_64 i386" \
    HEADER_SEARCH_PATHS="$PROJECT_ROOT/lua $PROJECT_ROOT/NetHack/include $PROJECT_ROOT/NetHack/sys/share" \
    OTHER_LDFLAGS="-lz" \
    -quiet || {
        echo -e "${RED}❌ Build fehlgeschlagen!${NC}"
        echo ""
        echo "Mögliche Lösungen:"
        echo "1. Stelle sicher, dass die Library aktuell ist: ./build_nethack_dylib.sh"
        echo "2. Überprüfe die Xcode Build Settings"
        echo "3. Schaue in die Xcode Logs für Details"
        exit 1
    }

# Copy fonts to app bundle
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/nethack-*/Index.noindex/Build/Products/Debug-iphonesimulator/nethack.app"
for app in $APP_PATH; do
    if [ -d "$app" ]; then
        echo -e "${YELLOW}[3/3] Kopiere Fonts in App Bundle...${NC}"
        mkdir -p "$app/Fonts"
        cp -v nethack/Fonts/*.ttf "$app/Fonts/"
        echo -e "${GREEN}Fonts kopiert nach: $app/Fonts/${NC}"
        break
    fi
done

echo ""
echo -e "${GREEN}✅ Build erfolgreich!${NC}"
echo ""
echo "App wurde gebaut für ARM64 (iPhone/iPad)"