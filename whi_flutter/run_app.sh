#!/bin/bash
# Run the Waffle House Index Flutter App on Linux

echo "Waffle House Index Flutter App"
echo "=============================="
echo ""
echo "Building app..."

# Build the app
flutter build linux --debug 2>&1 | grep -E "Built|error|failed"

if [ ! -f "build/linux/x64/debug/bundle/whi_flutter" ]; then
    echo "Build failed! Executable not found."
    exit 1
fi

# Build Flutter assets if needed
if [ ! -d "build/linux/x64/debug/bundle/data/flutter_assets" ] || [ ! -f "build/linux/x64/debug/bundle/data/flutter_assets/kernel_blob.bin" ]; then
    echo "Building Flutter assets..."
    flutter assemble \
        -dTargetPlatform=linux-x64 \
        -dTargetFile=lib/main.dart \
        -dBuildMode=debug \
        --output=build/flutter_assets \
        debug_bundle_linux-x64_assets

    # Copy assets
    mkdir -p build/linux/x64/debug/bundle/data/flutter_assets
    if [ -d "build/flutter_assets/flutter_assets" ]; then
        cp -r build/flutter_assets/flutter_assets/* build/linux/x64/debug/bundle/data/flutter_assets/
    else
        cp -r build/flutter_assets/* build/linux/x64/debug/bundle/data/flutter_assets/
    fi
fi

echo ""
echo "Starting app..."
echo "Note: The app will open in a new window."
echo "      On Linux desktop, it uses Atlanta, GA as the default location."
echo "      Press Ctrl+C in this terminal to stop the app."
echo ""

# Run the app
cd build/linux/x64/debug/bundle
export LD_LIBRARY_PATH="./lib:$LD_LIBRARY_PATH"
./whi_flutter