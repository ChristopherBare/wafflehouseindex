# Waffle House Index — Flutter App

A Flutter application that displays the Waffle House Index for locations within a 50 mile radius of the user's current location.

## Status: ✅ Working with Django Backend API

### What's New (January 2026)
- **NEW**: Django REST API backend for reliable data fetching
- **NEW**: Android support with automatic API URL detection
- **Fixed**: App now uses API instead of web scraping (more reliable)
- **Fixed**: "No implementation found for isLocationServiceEnabled" error on Linux
- **Added**: Fallback to Atlanta, GA location for desktop/emulator testing
- **Added**: Retry logic for initial API connection
- **Working**: App runs on Linux desktop and Android with Django backend

## Features
- **NEW: Adjustable radius slider** (10-100 miles) with live updates
- **NEW: Visual status indicator** with severity levels:
  - 🟢 All Clear (≥95% open) - Normal operations
  - 🟢 Minor Impact (80-94% open) - Some locations affected
  - 🟠 Moderate Alert (60-79% open) - Significant regional impact
  - 🟠 Severe Alert (40-59% open) - Major disaster conditions
  - 🔴 Critical Alert (<40% open) - Catastrophic conditions
- Shows nearby Waffle House locations within adjustable radius
- Displays open/closed status for each location
- Calculates the Waffle House Index (percentage open)
- Pull-to-refresh functionality
- Works on Android, iOS, Web, and Linux desktop

## Setup

### Backend Setup (Required)

The Flutter app now requires the Django backend API to be running:

```bash
# Navigate to backend directory
cd ../whi_backend

# Install Python dependencies
pip install -r requirements.txt

# Run migrations
python manage.py migrate

# Start the Django server
python manage.py runserver 0.0.0.0:8000

# The API will be available at http://localhost:8000/api/
# Test it: curl http://localhost:8000/api/health/
```

### API Endpoints
- `GET /api/health/` - Health check
- `GET /api/index/coordinates/?lat=<lat>&lon=<lon>&radius=<radius>` - Get index by coordinates
- `GET /api/index/zip/?zip=<zip>&radius=<radius>` - Get index by ZIP code
- `GET /api/locations/` - Get all locations with status

### Flutter App Prerequisites
```bash
# Install Flutter (if not already installed)
# See https://flutter.dev/docs/get-started/install

# Enable Linux desktop support
flutter config --enable-linux-desktop

# Install Linux dependencies
# Ubuntu/Debian:
sudo apt install libgtk-3-dev cmake ninja-build clang

# Fedora:
sudo dnf install gtk3-devel cmake ninja-build clang
```

### Installation
```bash
# Get packages
flutter pub get

# Run the app on Linux
flutter run -d linux

# Run the app on Android
flutter run -d android

# Or use the helper scripts
./run_linux.sh           # Run on Linux desktop
./run_android.sh         # Run on Android emulator/device
./run_with_fallback.sh   # Run with debug output
```

### Android Setup

For detailed Android setup instructions, see [ANDROID_SETUP.md](ANDROID_SETUP.md).

Quick steps:
1. Start Android emulator in Android Studio/IntelliJ
2. Run `./run_android.sh`
3. Grant location permission when prompted

## Configuration

### API Server URL

The app automatically detects the platform and uses the appropriate API URL:

- **Linux/Desktop**: `http://localhost:8000`
- **Android Emulator**: `http://10.0.2.2:8000` (special IP for host)
- **Android Device**: Update line 236 in `lib/main.dart` with your computer's IP
- **Web**: `http://localhost:8000`

For physical Android devices, edit `lib/main.dart`:
```dart
// Line 236 - Replace with your computer's IP address
return 'http://192.168.1.100:8000';
```

Find your IP address:
```bash
# Linux/Mac
ip addr show | grep inet

# Windows
ipconfig | findstr IPv4
```

## Location Services on Linux

The app handles location services gracefully on Linux:

1. **With Location Services**: If you have geoclue/location services configured, the app will use your actual location
2. **Without Location Services**: The app automatically falls back to Atlanta, GA as a default location for testing
3. **Visual Indicator**: When using the fallback location, the app displays "Using Atlanta, GA as default location" in orange

### Setting up Location Services (Optional)
If you want to use actual location on Linux:
```bash
# Install geoclue
sudo apt install geoclue-2.0  # Ubuntu/Debian
sudo dnf install geoclue2      # Fedora

# Start the service
sudo systemctl start geoclue
```

## Building

### Debug Build
```bash
flutter build linux --debug
./build/linux/x64/debug/bundle/whi_flutter
```

### Release Build
```bash
flutter build linux --release
./build/linux/x64/release/bundle/whi_flutter
```

## Testing
```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Use the helper script
./run_tests.sh
```

## Data Sources
- **Django Backend API**: Local server at `http://localhost:8000/api/`
- Backend fetches data from https://locations.wafflehouse.com (Next.js `__NEXT_DATA__`)
- Reliable data extraction handled by the Python backend
- All location data including status comes from the API

## Status Determination
The app determines if a location is open based on the `_status` field:
- `_status: "A"` = Active/Open ✅
- Any other value = Closed ❌

This matches the Python script implementation that works reliably.

## Permissions
- **Android**: Location permissions required (handled automatically)
- **iOS**: NSLocationWhenInUseUsageDescription in Info.plist
- **Web**: Browser will prompt for location permission
- **Linux**: Falls back to default location if not available

## Troubleshooting

### "No implementation found for isLocationServiceEnabled" Error
**Fixed!** The app now includes:
- geolocator_linux package for Linux support
- Automatic fallback to Atlanta, GA for testing
- Graceful error handling for missing location services

### CMake Errors on Linux
If you get CMake errors:
```bash
rm -rf build/linux
flutter clean
flutter pub get
flutter build linux --debug
```

### Missing Flutter Libraries
The app will automatically copy required Flutter libraries during build. If issues persist:
```bash
flutter precache --linux
```

## Project Structure
```
whi_flutter/
├── lib/
│   └── main.dart          # Main app code with location fallback
├── test/
│   ├── widget_test.dart   # Widget tests
│   └── integration_test.dart # Integration tests
├── linux/                 # Linux platform files
├── pubspec.yaml          # Dependencies (includes geolocator_linux)
├── run_linux.sh          # Build and run script
├── run_with_fallback.sh  # Run with debug output
└── run_tests.sh          # Test runner script
```

## Notes
- Endpoints may change without notice; use responsibly
- Distance calculations use straight-line distance (as the crow flies)
- The status reflects website data and may not reflect real-time operations