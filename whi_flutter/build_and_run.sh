#!/bin/bash
# Complete build and run script for Flutter app on Linux

set -e

echo "Waffle House Index Flutter App - Linux Build & Run"
echo "=================================================="
echo ""

# Clean previous build
echo "Cleaning previous build..."
rm -rf build/linux

# Build the app
echo "Building Flutter app..."
flutter build linux --debug

# Ensure Flutter assets are built
echo "Building Flutter assets..."
flutter assemble \
  -dTargetPlatform=linux-x64 \
  -dTargetFile=lib/main.dart \
  -dBuildMode=debug \
  --output=build/flutter_assets \
  debug_bundle_linux-x64_assets

# Create data directory structure
echo "Setting up bundle directory..."
BUNDLE_DIR="build/linux/x64/debug/bundle"
mkdir -p "$BUNDLE_DIR/data/flutter_assets"
mkdir -p "$BUNDLE_DIR/lib"

# Copy Flutter assets (flatten the nested structure)
if [ -d "build/flutter_assets/flutter_assets" ]; then
  cp -r build/flutter_assets/flutter_assets/* "$BUNDLE_DIR/data/flutter_assets/"
else
  cp -r build/flutter_assets/* "$BUNDLE_DIR/data/flutter_assets/"
fi

# Copy ICU data
if [ -f "linux/flutter/ephemeral/icudtl.dat" ]; then
  cp linux/flutter/ephemeral/icudtl.dat "$BUNDLE_DIR/data/"
fi

# Copy Flutter engine libraries
if [ -f "linux/flutter/ephemeral/libflutter_linux_gtk.so" ]; then
  cp linux/flutter/ephemeral/*.so "$BUNDLE_DIR/lib/" 2>/dev/null || true
fi

echo ""
echo "Build complete! Bundle structure:"
echo "  Executable: $BUNDLE_DIR/whi_flutter"
echo "  Assets: $BUNDLE_DIR/data/flutter_assets/"
echo "  Libraries: $BUNDLE_DIR/lib/"
echo ""

# Run the app
echo "Starting app..."
echo "Note: On Linux desktop, the app will use Atlanta, GA as the default location"
echo ""

cd "$BUNDLE_DIR"
export LD_LIBRARY_PATH="./lib:$LD_LIBRARY_PATH"
./whi_flutter