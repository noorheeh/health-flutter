# HKObserverQuery Feature - Real-time Health Data Observation

This document describes how to use the HKObserverQuery feature for real-time health data updates on iOS.

## Overview

The HKObserverQuery feature allows your app to receive real-time notifications when health data changes in HealthKit. This is useful for:
- Monitoring specific health metrics in real-time
- Building dashboards that auto-update when new data arrives
- Responding to health events immediately without polling

**Note:** This is an iOS-only feature. Android/Health Connect does not have an equivalent API.

## Architecture

The feature uses Flutter's EventChannel to stream updates:
- **Existing MethodChannel** (`flutter_health`): Request-response queries (unchanged)
- **New EventChannel** (`flutter_health/observer`): Real-time push updates

## iOS Setup

### 1. Enable Background Modes (Optional)

If you want to receive updates when your app is in the background:

1. Open your iOS project in Xcode: `ios/Runner.xcworkspace`
2. Select your target → **Signing & Capabilities**
3. Click **+ Capability** → Add **Background Modes**
4. Enable **Background fetch** and **Background processing**

### 2. Configure Info.plist

Add the following to your `ios/Runner/Info.plist` if using background delivery:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
    <string>fetch</string>
</array>
```

### 3. Request Permissions

Make sure you've requested read permissions for the data types you want to observe using the existing `requestAuthorization` method.

## Dart/Flutter Usage

### Sample Flow

The repository's `example/lib/main.dart` demonstrates this API with UI controls to start/stop observation, toggle background delivery, and view a live log. The flow looks like this:

```dart
final health = Health();
StreamSubscription<HealthObserverUpdate>? subscription;

void startObserver() {
  subscription = health.observeHealthData(
    types: const [
      HealthDataType.STEPS,
      HealthDataType.HEART_RATE,
    ],
    enableBackground: false,
  ).listen(
    (update) async {
      if (update.type == HealthObserverEventType.update &&
          update.dataType != null) {
        await _fetchLatestData(update.dataType!);
      }
    },
    onError: (error) {
      debugPrint('Observer stream error: $error');
    },
    cancelOnError: false,
  );
}

void stopObserver() {
  subscription?.cancel();
  health.stopObservingHealthData();
}
```

### Handling Events

A `HealthObserverUpdate` encodes the event type, the HealthKit sample key, an optional timestamp (ms) and error string. Typical handling:

```dart
void handleUpdate(HealthObserverUpdate update) {
  switch (update.type) {
    case HealthObserverEventType.update:
      debugPrint('New ${update.dataType} sample at ${update.timestamp}');
      break;
    case HealthObserverEventType.error:
      debugPrint('Observer error: ${update.error}');
      break;
    case HealthObserverEventType.backgroundDeliveryEnabled:
      debugPrint('Background delivery enabled for ${update.dataType}');
      break;
    case HealthObserverEventType.backgroundDeliveryError:
      debugPrint('Background delivery failed: ${update.error}');
      break;
  }
}
```

## Event Types

The observer emits `HealthObserverUpdate` objects with the following event types:

### `HealthObserverEventType.update`
New health data is available for the specified data type.

```dart
HealthObserverUpdate(
  type: HealthObserverEventType.update,
  dataType: HealthDataType.STEPS,
  timestamp: 1234567890,  // Milliseconds since epoch
  error: null,
)
```

### `HealthObserverEventType.error`
An error occurred during observation.

```dart
HealthObserverUpdate(
  type: HealthObserverEventType.error,
  dataType: HealthDataType.HEART_RATE,
  timestamp: null,
  error: 'Error description',
)
```

### `HealthObserverEventType.backgroundDeliveryEnabled`
Background delivery was successfully enabled.

```dart
HealthObserverUpdate(
  type: HealthObserverEventType.backgroundDeliveryEnabled,
  dataType: HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
  timestamp: null,
  error: null,
)
```

### `HealthObserverEventType.backgroundDeliveryError`
An error occurred while enabling background delivery.

```dart
HealthObserverUpdate(
  type: HealthObserverEventType.backgroundDeliveryError,
  dataType: HealthDataType.STEPS,
  timestamp: null,
  error: 'Error description',
)
```

## Important Notes

### iOS Specific
- **Platform Check**: Always wrap observer code with platform checks
- **Background Limits**: iOS may throttle background updates
- **Battery Impact**: Background observation can impact battery life
- **Permissions**: Requires read permission for observed data types

### Android
- This feature is **not available on Android**
- Health Connect doesn't provide a real-time observation API
- Consider implementing polling for Android if needed

### Best Practices

1. **Observe Only What You Need**: Don't observe all data types
2. **Disable When Not Needed**: Stop observing when your widget is disposed
3. **Fetch Data on Update**: The observer only notifies of changes; use `getData()` to fetch actual values
4. **Handle Errors**: Always implement error handling
5. **Test Background Behavior**: Background updates may not work in debug mode

## Platform-Specific Code Example

```dart
import 'dart:io';
import 'dart:async';
import 'package:health/health.dart';

void setupObserver() {
  final health = Health();

  if (Platform.isIOS) {
    // Use HKObserverQuery on iOS - real-time updates
    health.observeHealthData(
      types: [HealthDataType.STEPS],
      enableBackground: true,
    ).listen((update) {
      if (update.type == HealthObserverEventType.update) {
        _fetchHealthData();
      }
    });
  } else if (Platform.isAndroid) {
    // Use polling on Android - Health Connect doesn't support observers
    Timer.periodic(Duration(minutes: 5), (timer) {
      _fetchHealthData();
    });
  }
}
```

## Troubleshooting

### Observer Not Receiving Updates
1. Verify permissions are granted for the data types
2. Check that the data types are valid for iOS
3. Ensure HealthKit is available on the device (not available in simulator for some types)

### Background Updates Not Working
1. Verify Background Modes are enabled in Xcode
2. Check Info.plist configuration
3. Test on a physical device (not simulator)
4. Background delivery requires the app to have been launched at least once

### Memory Leaks
Always dispose of the observer stream when no longer needed:
```dart
final Health _health = Health();

@override
void dispose() {
  _health.stopObservingHealthData();
  super.dispose();
}
```

## Performance Considerations

- **Battery Usage**: Background observation consumes battery
- **Frequency**: iOS controls update frequency; you cannot set custom intervals
- **Data Fetching**: Only fetch data when needed; don't store everything in memory
- **Stream Management**: Use broadcast streams for multiple listeners

## Migration from Polling

If you currently use polling:

**Before:**
```dart
Timer.periodic(Duration(minutes: 5), (timer) {
  _fetchHealthData();
});
```

**After:**
```dart
final health = Health();

health.observeHealthData(
  types: [HealthDataType.STEPS],
  enableBackground: true,
).listen((update) {
  if (update.type == HealthObserverEventType.update) {
    _fetchHealthData();
  }
});
```

This reduces battery usage and provides real-time updates.
