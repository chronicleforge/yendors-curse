#!/bin/bash

# Xcode Build Script - For Real iOS Device

set -e

echo "==========================================="
echo "Xcode Build - iOS Device (ARM64)"
echo "==========================================="

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}[1/3] Building device library...${NC}"
# SLOG enabled by default (set NH_STRUCTURED_LOGGING=0 to disable)
NH_STRUCTURED_LOGGING="${NH_STRUCTURED_LOGGING:-1}" ./build_nethack_device.sh

echo -e "${YELLOW}[2/3] Clean Build Directory...${NC}"
xcodebuild clean \
    -scheme nethack \
    -configuration Debug \
    -quiet

echo -e "${YELLOW}[3/3] Building for iOS Device (ARM64)...${NC}"
xcodebuild build \
    -scheme nethack \
    -configuration Debug \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    ARCHS=arm64 \
    VALID_ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    HEADER_SEARCH_PATHS="$PROJECT_ROOT/lua $PROJECT_ROOT/NetHack/include $PROJECT_ROOT/NetHack/sys/share" \
    OTHER_LDFLAGS="-lz" \
    -quiet || {
        echo -e "${RED}❌ Build failed!${NC}"
        echo ""
        echo "Possible solutions:"
        echo "1. Make sure universal library is up to date: ./build_nethack_universal.sh"
        echo "2. Check Xcode Build Settings"
        echo "3. Check if development team is configured"
        exit 1
    }

echo ""
echo -e "${GREEN}✅ Build successful!${NC}"
echo ""
echo "App built for iOS Device (ARM64)"
echo "You can now deploy to your iPhone/iPad"