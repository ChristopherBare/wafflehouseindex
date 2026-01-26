# Waffle House Index UI Features

## New Interactive Features (January 2026)

### 1. Status Indicator Card

The app now displays a prominent status card at the top showing the disaster severity level based on the percentage of open locations:

- **Visual Design**:
  - Colored card with icon that changes based on status
  - Border and background color match the severity level
  - Large icon in a circular badge
  - Clear status text with description

- **Severity Levels**:
  - **🟢 All Clear** (≥95% open) - Green - Normal operations, minimal impact
  - **🟢 Minor Impact** (80-94% open) - Light Green - Some locations affected
  - **🟠 Moderate Alert** (60-79% open) - Orange - Significant regional impact
  - **🟠 Severe Alert** (40-59% open) - Deep Orange - Major disaster conditions
  - **🔴 Critical Alert** (<40% open) - Red - Catastrophic conditions

### 2. Radius Slider

An interactive slider allows you to adjust the search radius on the fly:

- **Range**: 10 to 100 miles
- **Live Updates**: Data refreshes automatically when you move the slider
- **Visual Feedback**:
  - Current radius displayed prominently above the slider
  - Min/Max labels (10 mi - 100 mi) below the slider
  - Progress indicator shows when data is loading
  - Slider is disabled during data refresh to prevent conflicts

### 3. Enhanced Statistics Card

The statistics card now shows:
- Total number of nearby stores within selected radius
- Number and percentage of open locations
- Number and percentage of closed locations
- Location source indicator (GPS or fallback to Atlanta, GA)

### 4. Improved Location List

Each Waffle House location shows:
- ✅ Green check for open locations
- ❌ Red X for closed locations
- Store name and number
- City and state
- Distance from your location

## User Experience Improvements

### Performance Optimizations
- **Cached Position**: Location is cached after first request to avoid repeated GPS calls
- **Retry Logic**: API calls retry up to 3 times with exponential backoff
- **Loading States**: Clear visual feedback during data updates

### Platform-Specific Features
- **Android**: Automatically uses `10.0.2.2:8000` for emulator connections
- **Linux/Desktop**: Uses `localhost:8000`
- **Physical Devices**: Configurable IP address for network access

### Responsive Design
- Cards with rounded corners and elevation
- Color-coded severity indicators
- Smooth animations when updating
- Pull-to-refresh functionality

## How to Use

1. **Launch the App**: Start with default 50-mile radius
2. **Adjust Radius**: Slide to change search area (10-100 miles)
3. **Check Status**: View the color-coded status indicator
4. **Browse Locations**: Scroll through nearby Waffle House locations
5. **Refresh**: Pull down to refresh data

## Technical Details

### API Integration
- Real-time data from Django backend
- Efficient radius-based queries
- Automatic platform detection for API URLs

### State Management
- Radius value persists during session
- Position cached to reduce GPS calls
- Loading states prevent conflicting updates

### Error Handling
- Graceful fallback to Atlanta, GA if location unavailable
- Retry logic for network failures
- Clear error messages for troubleshooting