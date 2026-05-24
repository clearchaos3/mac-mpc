#!/bin/bash
# Builds the project and wraps the binary in a proper .app bundle.
# Output: ./mac-mpc.app  →  open it with `open ./mac-mpc.app`

set -e

CONFIG=${1:-debug}
case "$CONFIG" in
    debug)   FLAGS="" ;;
    release) FLAGS="-c release" ;;
    *) echo "usage: $0 [debug|release]"; exit 1 ;;
esac

echo "→ swift build $FLAGS"
swift build $FLAGS

ARCH=$(uname -m)
BIN_DIR=".build/${ARCH}-apple-macosx/$CONFIG"
APP_NAME="mac-mpc.app"
APP_ROOT="$APP_NAME/Contents"

rm -rf "$APP_NAME"
mkdir -p "$APP_ROOT/MacOS" "$APP_ROOT/Resources"

cp "$BIN_DIR/mac-mpc" "$APP_ROOT/MacOS/mac-mpc"
cp Sources/App/SupportFiles/Info.plist "$APP_ROOT/Info.plist"

if [ -f "Sources/App/SupportFiles/AppIcon.icns" ]; then
    cp Sources/App/SupportFiles/AppIcon.icns "$APP_ROOT/Resources/AppIcon.icns"
fi

# SwiftPM emits a resource bundle alongside the binary; fold it into Resources/.
if [ -d "$BIN_DIR/mac-mpc_App.bundle" ]; then
    cp -R "$BIN_DIR/mac-mpc_App.bundle" "$APP_ROOT/Resources/"
fi

chmod +x "$APP_ROOT/MacOS/mac-mpc"

echo ""
echo "✓ Built $APP_NAME"
echo "  Open it with:  open \"./$APP_NAME\""
