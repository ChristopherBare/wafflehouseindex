#!/bin/bash

# Script to run the Waffle House Index app on Android emulator

echo "==============================================="
echo "Running Waffle House Index on Android"
echo "==============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Django backend is running
echo -e "\n${YELLOW}Checking Django backend...${NC}"
if curl -s http://localhost:8000/api/health/ > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Backend API is running${NC}"
else
    echo -e "${RED}✗ Backend API is not running!${NC}"
    echo ""
    echo "Please start the Django backend first:"
    echo "  cd ../whi_backend"
    echo "  python manage.py runserver 0.0.0.0:8000"
    echo ""
    echo "Or use the full app script from the project root:"
    echo "  ./run_full_app.sh"
    exit 1
fi

# Check for available Android devices/emulators
echo -e "\n${YELLOW}Checking for Android devices...${NC}"
DEVICES=$(flutter devices | grep -E "android|emulator" | head -1)

if [ -z "$DEVICES" ]; then
    echo -e "${RED}No Android devices found!${NC}"
    echo ""
    echo "Please either:"
    echo "1. Start an Android emulator in Android Studio/IntelliJ"
    echo "2. Connect a physical Android device with USB debugging enabled"
    echo ""
    echo "To list available devices:"
    echo "  flutter devices"
    exit 1
fi

echo -e "${GREEN}✓ Android device found${NC}"
echo "$DEVICES"

# Run the app
echo -e "\n${GREEN}Starting Flutter app on Android...${NC}"
echo -e "${YELLOW}Note: The app will request location permission on first run${NC}"
echo -e "${YELLOW}The API URL will automatically use 10.0.2.2:8000 for emulator${NC}"
echo ""

flutter run -d android

echo -e "\n${GREEN}App terminated${NC}"