#!/bin/bash
# Script to build and run the Flutter app on Linux

echo "Building Flutter app for Linux..."
flutter build linux --debug

if [ $? -eq 0 ]; then
    echo "Build successful! Starting app..."
    ./build/linux/x64/debug/bundle/whi_flutter
else
    echo "Build failed!"
    exit 1
fi