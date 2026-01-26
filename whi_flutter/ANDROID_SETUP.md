# Android Setup for Waffle House Index App

## Prerequisites

1. **Android Studio or IntelliJ IDEA** with Android plugin
2. **Android SDK** (API level 21 or higher)
3. **Android Emulator** or physical device
4. **Django backend** running (see main README)

## Quick Start

### 1. Start the Django Backend

```bash
cd ../whi_backend
python manage.py runserver 0.0.0.0:8000
```

### 2. Start Android Emulator

#### Option A: Using Android Studio/IntelliJ
1. Open Android Studio or IntelliJ IDEA
2. Open AVD Manager (Tools → AVD Manager)
3. Create or start an Android emulator

#### Option B: Command Line
```bash
# List available emulators
emulator -list-avds

# Start an emulator
emulator -avd <emulator_name>
```

### 3. Run the App

```bash
# From whi_flutter directory
./run_android.sh

# Or manually:
flutter run -d android
```

## IntelliJ IDEA Setup

### Create Run Configuration

1. Open the project in IntelliJ IDEA
2. Go to **Run → Edit Configurations**
3. Click **+** and select **Flutter**
4. Configure:
   - **Name**: WHI Android
   - **Dart entrypoint**: `lib/main.dart`
   - **Flutter SDK path**: (auto-detected)
   - **Build flavor**: (leave empty)
   - **Additional run args**: `-d android`

### Running from IntelliJ

1. Select "WHI Android" from the run configuration dropdown
2. Click the green **Run** button or press **Shift+F10**
3. The app will build and deploy to the emulator/device

## Network Configuration

The app automatically detects the platform and uses the correct API URL:

- **Android Emulator**: `http://10.0.2.2:8000` (special IP for host machine)
- **Physical Device**: Update line 236 in `lib/main.dart` with your computer's IP:
  ```dart
  return 'http://192.168.1.100:8000';  // Replace with your IP
  ```

To find your computer's IP:
```bash
# Linux/Mac
ip addr show | grep inet
# or
ifconfig | grep inet

# Windows
ipconfig | findstr IPv4
```

## Permissions

The app requests the following permissions:
- **Internet**: For API calls (automatically granted)
- **Location**: For getting user's position (requested at runtime)

## Troubleshooting

### App Can't Connect to API

1. **Emulator**: Ensure you're using `10.0.2.2` not `localhost`
2. **Physical Device**:
   - Update the IP address in `lib/main.dart`
   - Ensure device is on same network as computer
   - Check firewall settings

### Location Not Working

- The app will fall back to Atlanta, GA if location is unavailable
- Grant location permission when prompted
- Check location settings on the device

### Build Issues

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run -d android
```

### Check Device Connection

```bash
# List connected devices
flutter devices

# Should show something like:
# • Android SDK built for x86 (emulator-5554) • android-x86 • Android 11 (API 30)
```

## Hot Reload

While the app is running:
- Press **r** for hot reload (updates UI instantly)
- Press **R** for hot restart (restarts app state)

## Building APK

To create a release APK:

```bash
# Build release APK
flutter build apk --release

# The APK will be at:
# build/app/outputs/flutter-apk/app-release.apk
```

## API Server Requirements

The Django backend must be running and accessible:
- Use `0.0.0.0:8000` when starting Django (not just `localhost:8000`)
- This allows connections from other devices on the network

```bash
python manage.py runserver 0.0.0.0:8000
```