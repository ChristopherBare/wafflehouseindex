#!/bin/bash
# Run the Flutter app with location fallback for Linux desktop

echo "Starting Waffle House Index app..."
echo "================================="
echo ""
echo "Note: On Linux desktop, the app will use Atlanta, GA as the default location"
echo "since native location services may not be available."
echo ""
echo "Building app..."
flutter build linux --debug

if [ $? -eq 0 ]; then
    echo ""
    echo "Starting app (check for the GUI window)..."
    echo "You should see output like 'Using default location (Atlanta, GA) for testing'"
    echo ""
    ./build/linux/x64/debug/bundle/whi_flutter 2>&1 | grep -E "Mock|default|Atlanta|flutter:" &
    APP_PID=$!
    echo "App started with PID: $APP_PID"
    echo "Press Ctrl+C to stop the app"
    wait $APP_PID
else
    echo "Build failed!"
    exit 1
fi