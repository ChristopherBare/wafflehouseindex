#!/bin/bash
# Test the updated Flutter app that uses Next.js data extraction

echo "==========================================="
echo "Testing Updated Waffle House Index App"
echo "==========================================="
echo ""
echo "This version uses the same data extraction"
echo "method as the Python script (Next.js data)"
echo ""

# Build the app
echo "Building app..."
flutter build linux --debug 2>&1 | grep -E "Built|error|failed"

if [ ! -f "build/linux/x64/debug/bundle/whi_flutter" ]; then
    echo "Build failed!"
    exit 1
fi

# Ensure assets are present
if [ ! -f "build/linux/x64/debug/bundle/data/flutter_assets/kernel_blob.bin" ]; then
    echo "Copying Flutter assets..."
    cd /home/christopher/IdeaProjects/wafflehouseindex/whi_flutter
    flutter assemble \
        -dTargetPlatform=linux-x64 \
        -dTargetFile=lib/main.dart \
        -dBuildMode=debug \
        --output=build/flutter_assets \
        debug_bundle_linux-x64_assets

    mkdir -p build/linux/x64/debug/bundle/data/flutter_assets
    if [ -d "build/flutter_assets/flutter_assets" ]; then
        cp -r build/flutter_assets/flutter_assets/* build/linux/x64/debug/bundle/data/flutter_assets/
    else
        cp -r build/flutter_assets/* build/linux/x64/debug/bundle/data/flutter_assets/
    fi
fi

echo ""
echo "Starting app (GUI will open in a new window)..."
echo "- Uses Atlanta, GA as default location on Linux"
echo "- Data extraction method: Next.js __NEXT_DATA__"
echo "- Status based on _status field (A = Open)"
echo ""
echo "Press Ctrl+C to stop"
echo ""

cd build/linux/x64/debug/bundle
export LD_LIBRARY_PATH="./lib:$LD_LIBRARY_PATH"
./whi_flutter