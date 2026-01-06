# HKObserverQuery Feature - Real-time Health Data Observation

This document describes how to use the enhanced HKObserverQuery feature for real-time health data updates on iOS.

## Overview

The observer feature allows your app to receive real-time notifications when health data changes in HealthKit. Key capabilities:

- **Real-time updates** when health data changes
- **Actual data included** (optional) - no need for separate fetch calls
- **Anchor-based tracking** - only receive truly new data
- **Background support** - receive updates while app is backgrounded
- **Persistent background** - receive updates even when app is terminated
- **Deleted data tracking** - know when samples are removed

**Note:** This is an iOS-only feature. Android/Health Connect does not have an equivalent real-time API.

## Quick Start

### Basic Usage (Notification Only)

```dart
final health = Health();

health.observeHealthData(
  types: [HealthDataType.STEPS, HealthDataType.HEART_RATE],
).listen((update) {
  if (update.type == HealthObserverEventType.update) {
    print('New ${update.dataType} data available');
    // Fetch data manually if needed
  }
});
```

### With Data (Recommended)

```dart
health.observeHealthData(
  types: [HealthDataType.STEPS, HealthDataType.HEART_RATE],
  includeData: true,  // Data included in update!
  enableBackground: true,
).listen((update) {
  if (update.type == HealthObserverEventType.update) {
    print('Added: ${update.addedCount} samples');
    print('Deleted: ${update.deletedCount} samples');

    // Access actual data
    for (final sample in update.addedSamples ?? []) {
      print('Value: ${sample['value']} at ${sample['date_from']}');
    }

    // Check if data is backdated (added with past timestamp)
    if (update.isBackdated()) {
      print('This data is from the past');
    }
  }
});
```

## Architecture

The enhanced observer uses `HKAnchoredObjectQuery` instead of `HKObserverQuery`:

| Feature | HKObserverQuery | HKAnchoredObjectQuery |
|---------|-----------------|----------------------|
| Notification | Yes | Yes |
| Returns data | No | Yes |
| Tracks anchor | No | Yes |
| Deleted samples | No | Yes |

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Data Flow                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   HealthKit  ──►  HKAnchoredObjectQuery  ──►  EventChannel  ──►  Dart
│                                                                      │
│   • New samples arrive                                              │
│   • Query returns added/deleted samples                             │
│   • Anchor updated (tracks position)                                │
│   • Data serialized and sent to Flutter                             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## iOS Setup

### 1. Enable Background Modes (Optional)

For background updates:

1. Open iOS project in Xcode: `ios/Runner.xcworkspace`
2. Select target → **Signing & Capabilities**
3. Click **+ Capability** → Add **Background Modes**
4. Enable **Background fetch** and **Background processing**

### 2. Configure Info.plist

```xml
<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
    <string>fetch</string>
</array>
```

### 3. AppDelegate Setup (For Terminated State)

To receive updates when app is terminated, add to `AppDelegate.swift`:

```swift
import Flutter
import UIKit
import health  // Import the health package

@main
class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Register persistent observers at app launch
        HealthBackgroundHandler.registerPersistentObservers()

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
```

## API Reference

### observeHealthData

```dart
Stream<HealthObserverUpdate> observeHealthData({
  required List<HealthDataType> types,
  bool enableBackground = false,
  bool includeData = false,
})
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `types` | `List<HealthDataType>` | Health data types to observe |
| `enableBackground` | `bool` | Enable background delivery |
| `includeData` | `bool` | Include actual samples in updates |

### HealthObserverUpdate

| Property | Type | Description |
|----------|------|-------------|
| `type` | `HealthObserverEventType` | Event type |
| `dataType` | `HealthDataType?` | The health type that changed |
| `timestamp` | `int?` | When the change occurred (ms) |
| `addedCount` | `int?` | Number of added samples |
| `deletedCount` | `int?` | Number of deleted samples |
| `addedSamples` | `List<Map>?` | Actual sample data (when includeData=true) |
| `deletedUUIDs` | `List<String>?` | UUIDs of deleted samples |
| `isBackgroundUpdate` | `bool` | Whether from background |
| `error` | `String?` | Error message if applicable |

#### Sample Data Format

When `includeData: true`, each sample in `addedSamples` contains:

```dart
{
  'uuid': 'A91A2F10-3D7B-486A-B140-5ADCD3C9C6D0',
  'date_from': 1704067200000,  // Activity start (ms since epoch)
  'date_to': 1704070800000,    // Activity end (ms since epoch)
  'value': 5432.0,             // The health value
  'unit': 'count',             // Unit string
  'source_id': 'com.apple.Health',
  'source_name': 'Health',
}
```

### Event Types

```dart
enum HealthObserverEventType {
  update,                    // New data available
  error,                     // Observation error
  backgroundDeliveryEnabled, // Background mode active
  backgroundDeliveryError,   // Background setup failed
}
```

### Helper Methods

```dart
// Check if data is backdated (happened before threshold)
bool isBackdated({Duration threshold = const Duration(hours: 1)})
```

## Persistent Background

For updates when app is terminated:

### 1. Register Types in Dart

```dart
// Call once during app setup
await health.registerBackgroundTypes(
  types: [HealthDataType.STEPS, HealthDataType.HEART_RATE],
);
```

### 2. Handle Pending Updates

```dart
// On app startup
Future<void> checkPendingUpdates() async {
  final pending = await health.getPendingBackgroundUpdates();

  for (final update in pending) {
    print('Missed: ${update.dataType} at ${update.timestamp}');
    if (update.isBackgroundUpdate) {
      // This update came while app was terminated
    }
  }

  // Clear after processing
  await health.clearPendingUpdates();
}
```

## Detecting Backdated Data

Know when data was added with a past timestamp:

```dart
health.observeHealthData(
  types: [HealthDataType.STEPS],
  includeData: true,
).listen((update) {
  if (update.type == HealthObserverEventType.update) {
    // Method 1: Use helper
    if (update.isBackdated(threshold: Duration(hours: 1))) {
      print('Data is from more than 1 hour ago');
    }

    // Method 2: Check manually
    for (final sample in update.addedSamples ?? []) {
      final activityTime = DateTime.fromMillisecondsSinceEpoch(sample['date_from']);
      final age = DateTime.now().difference(activityTime);

      if (age.inHours > 1) {
        print('Backdated: activity was ${age.inHours} hours ago');
      } else {
        print('Recent: activity just happened');
      }
    }
  }
});
```

## Complete Example

```dart
import 'dart:io';
import 'package:health/health.dart';

class HealthObserverService {
  final Health _health = Health();
  StreamSubscription<HealthObserverUpdate>? _subscription;

  Future<void> initialize() async {
    // Request permissions first
    await _health.requestAuthorization([
      HealthDataType.STEPS,
      HealthDataType.HEART_RATE,
    ]);

    // Register for persistent background (optional)
    if (Platform.isIOS) {
      await _health.registerBackgroundTypes(
        types: [HealthDataType.STEPS, HealthDataType.HEART_RATE],
      );

      // Check for updates from when app was terminated
      await _checkPendingUpdates();
    }
  }

  Future<void> _checkPendingUpdates() async {
    final pending = await _health.getPendingBackgroundUpdates();
    for (final update in pending) {
      _handleUpdate(update);
    }
    await _health.clearPendingUpdates();
  }

  void startObserving() {
    if (!Platform.isIOS) {
      print('Observer not available on Android');
      return;
    }

    _subscription = _health.observeHealthData(
      types: [HealthDataType.STEPS, HealthDataType.HEART_RATE],
      enableBackground: true,
      includeData: true,
    ).listen(
      _handleUpdate,
      onError: (error) => print('Error: $error'),
    );
  }

  void _handleUpdate(HealthObserverUpdate update) {
    switch (update.type) {
      case HealthObserverEventType.update:
        print('New ${update.dataType} data:');
        print('  Added: ${update.addedCount}');
        print('  Deleted: ${update.deletedCount}');

        if (update.isBackdated()) {
          print('  (Contains backdated data)');
        }

        for (final sample in update.addedSamples ?? []) {
          print('  Value: ${sample['value']} ${sample['unit']}');
        }
        break;

      case HealthObserverEventType.error:
        print('Observer error: ${update.error}');
        break;

      case HealthObserverEventType.backgroundDeliveryEnabled:
        print('Background delivery enabled for ${update.dataType}');
        break;

      case HealthObserverEventType.backgroundDeliveryError:
        print('Background delivery failed: ${update.error}');
        break;
    }
  }

  void stopObserving() {
    _subscription?.cancel();
    _health.stopObservingHealthData();
  }
}
```

## Troubleshooting

### Observer Not Receiving Updates
1. Verify permissions are granted
2. Check that data types are valid for iOS
3. Test on physical device (simulator has limitations)

### Background Updates Not Working
1. Verify Background Modes in Xcode
2. Check Info.plist configuration
3. Test on physical device
4. App must have been launched at least once

### Not Getting Actual Data
1. Ensure `includeData: true` is set
2. Check that samples exist for the data type

### Anchor Issues
- Anchors are persisted per data type
- First observation may return all existing data
- Subsequent observations only return new data

## Platform Comparison

| Feature | iOS | Android |
|---------|-----|---------|
| Real-time observer | Yes | No |
| Returns actual data | Yes | N/A |
| Background updates | Yes | No |
| Terminated updates | Yes (with setup) | No |
| Alternative | - | Polling with Changes API |

For Android, use polling:
```dart
if (Platform.isAndroid) {
  Timer.periodic(Duration(minutes: 5), (_) async {
    final data = await health.getHealthDataFromTypes(...);
    // Process data
  });
}
```

## Migration from v1 Observer

If upgrading from the previous observer implementation:

**Before (v1):**
```dart
health.observeHealthData(
  types: [HealthDataType.STEPS],
  enableBackground: true,
).listen((update) {
  // Had to fetch data separately
  final data = await health.getHealthDataFromTypes(...);
});
```

**After (v2):**
```dart
health.observeHealthData(
  types: [HealthDataType.STEPS],
  enableBackground: true,
  includeData: true,  // NEW: data included!
).listen((update) {
  // Data already available
  for (final sample in update.addedSamples ?? []) {
    print(sample['value']);
  }
});
```

The v1 API still works (backward compatible) - just omit `includeData`.
