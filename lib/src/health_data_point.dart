part of '../health.dart';

/// Types of health platforms.
enum HealthPlatformType { appleHealth, googleHealthConnect }

/// A [HealthDataPoint] object corresponds to a data point capture from
/// Apple HealthKit or Google Health Connect with a [HealthValue]
/// as value.
@JsonSerializable(includeIfNull: false, explicitToJson: true)
class HealthDataPoint {
  /// UUID of the data point.
  String uuid;

  /// The quantity value of the data point
  HealthValue value;

  /// The type of the data point.
  HealthDataType type;

  /// The data point type as a string.
  String get typeString => type.name;

  /// The unit of the data point.
  HealthDataUnit unit;

  /// The data point unit as a string.
  String get unitString => unit.name;

  /// The start of the time interval.
  DateTime dateFrom;

  /// The end of the time interval.
  DateTime dateTo;

  /// The health platform that this data point was fetched.
  HealthPlatformType sourcePlatform;

  /// The id of the device from which the data point was fetched.
  String sourceDeviceId;

  /// The id of the source from which the data point was fetched.
  String sourceId;

  /// The name of the source from which the data point was fetched.
  String sourceName;

  /// How the data point was recorded
  /// (on Android: https://developer.android.com/reference/kotlin/androidx/health/connect/client/records/metadata/Metadata#summary)
  /// on iOS: either user entered or manual https://developer.apple.com/documentation/healthkit/hkmetadatakeywasuserentered)
  RecordingMethod recordingMethod;

  /// The summary of the workout data point, if available.
  WorkoutSummary? workoutSummary;

  /// The metadata for this data point.
  Map<String, dynamic>? metadata;

  /// The source of the data, whether from the iPhone or Watch or something else.
  /// Only available for iOS
  /// On Android: always return null
  String? deviceModel;

  /// The manufacturer of the device (e.g., "Apple")
  /// Only available for iOS
  /// On Android: always return null
  String? deviceManufacturer;

  /// The name of the device (e.g., "John's iPhone")
  /// Only available for iOS
  /// On Android: always return null
  String? deviceName;

  /// The hardware version of the device
  /// Only available for iOS
  /// On Android: always return null
  String? deviceHardwareVersion;

  /// The firmware version of the device (useful for external devices like Apple Watch)
  /// Only available for iOS
  /// On Android: always return null
  String? deviceFirmwareVersion;

  /// The software version of the device
  /// Only available for iOS
  /// On Android: always return null
  String? deviceSoftwareVersion;

  /// The local identifier of the device (private to your app)
  /// Only available for iOS
  /// On Android: always return null
  String? deviceLocalIdentifier;

  /// The UDI (Universal Device Identifier) for medical devices
  /// Only available for iOS
  /// On Android: always return null
  String? deviceUdiIdentifier;

  /// The product type from source revision (e.g., "iPhone18,1")
  /// Only available for iOS 11+
  /// On Android: always return null
  String? sourceProductType;

  /// The operating system version from source revision (e.g., "18.1.0")
  /// Only available for iOS 11+
  /// On Android: always return null
  String? sourceOsVersion;

  /// The app/source version that recorded the data
  /// Only available for iOS 11+
  /// On Android: always return null
  String? sourceVersion;

  HealthDataPoint({
    required this.uuid,
    required this.value,
    required this.type,
    required this.unit,
    required this.dateFrom,
    required this.dateTo,
    required this.sourcePlatform,
    required this.sourceDeviceId,
    required this.sourceId,
    required this.sourceName,
    this.recordingMethod = RecordingMethod.unknown,
    this.workoutSummary,
    this.metadata,
    this.deviceModel,
    this.deviceManufacturer,
    this.deviceName,
    this.deviceHardwareVersion,
    this.deviceFirmwareVersion,
    this.deviceSoftwareVersion,
    this.deviceLocalIdentifier,
    this.deviceUdiIdentifier,
    this.sourceProductType,
    this.sourceOsVersion,
    this.sourceVersion,
  }) {
    // set the value to minutes rather than the category
    // returned by the native API
    if (type == HealthDataType.MINDFULNESS ||
        type == HealthDataType.HEADACHE_UNSPECIFIED ||
        type == HealthDataType.HEADACHE_NOT_PRESENT ||
        type == HealthDataType.HEADACHE_MILD ||
        type == HealthDataType.HEADACHE_MODERATE ||
        type == HealthDataType.HEADACHE_SEVERE ||
        type == HealthDataType.SLEEP_ASLEEP ||
        type == HealthDataType.SLEEP_AWAKE ||
        type == HealthDataType.SLEEP_AWAKE_IN_BED ||
        type == HealthDataType.SLEEP_DEEP ||
        type == HealthDataType.SLEEP_IN_BED ||
        type == HealthDataType.SLEEP_LIGHT ||
        type == HealthDataType.SLEEP_REM ||
        type == HealthDataType.SLEEP_UNKNOWN ||
        type == HealthDataType.SLEEP_OUT_OF_BED) {
      value = _convertMinutes();
    }
  }

  /// Converts dateTo - dateFrom to minutes.
  NumericHealthValue _convertMinutes() =>
      NumericHealthValue(numericValue: (dateTo.millisecondsSinceEpoch - dateFrom.millisecondsSinceEpoch) / (1000 * 60));

  /// Create a [HealthDataPoint] from json.
  factory HealthDataPoint.fromJson(Map<String, dynamic> json) => _$HealthDataPointFromJson(json);

  /// Convert this [HealthDataPoint] to json.
  Map<String, dynamic> toJson() => _$HealthDataPointToJson(this);

  /// Create a [HealthDataPoint] based on a health data point from native data format.
  factory HealthDataPoint.fromHealthDataPoint(HealthDataType dataType, dynamic dataPoint, String? unitName) {
    // Handling different [HealthValue] types
    HealthValue value = switch (dataType) {
      HealthDataType.AUDIOGRAM => AudiogramHealthValue.fromHealthDataPoint(dataPoint),
      HealthDataType.WORKOUT => WorkoutHealthValue.fromHealthDataPoint(dataPoint),
      HealthDataType.WORKOUT_ROUTE => WorkoutRouteHealthValue.fromHealthDataPoint(dataPoint),
      HealthDataType.ELECTROCARDIOGRAM => ElectrocardiogramHealthValue.fromHealthDataPoint(dataPoint),
      HealthDataType.NUTRITION => NutritionHealthValue.fromHealthDataPoint(dataPoint),
      HealthDataType.INSULIN_DELIVERY => InsulinDeliveryHealthValue.fromHealthDataPoint(dataPoint),
      HealthDataType.MENSTRUATION_FLOW => MenstruationFlowHealthValue.fromHealthDataPoint(dataPoint),
      _ => NumericHealthValue.fromHealthDataPoint(dataPoint),
    };

    final DateTime from = DateTime.fromMillisecondsSinceEpoch(dataPoint['date_from'] as int);
    final DateTime to = DateTime.fromMillisecondsSinceEpoch(dataPoint['date_to'] as int);
    final String sourceId = dataPoint["source_id"] as String;
    final String sourceName = dataPoint["source_name"] as String;
    final Map<String, dynamic>? metadata = dataPoint["metadata"] == null
        ? null
        : Map<String, dynamic>.from(dataPoint['metadata'] as Map);
    final HealthDataUnit unit = HealthDataUnit.values.firstWhere(
      (value) => value.name == unitName,
      orElse: () => dataTypeToUnit[dataType] ?? HealthDataUnit.UNKNOWN_UNIT,
    );
    final String? uuid = dataPoint["uuid"] as String?;
    final String? deviceModel = dataPoint["device_model"] as String?;
    final String? deviceManufacturer = dataPoint["device_manufacturer"] as String?;
    final String? deviceName = dataPoint["device_name"] as String?;
    final String? deviceHardwareVersion = dataPoint["device_hardware_version"] as String?;
    final String? deviceFirmwareVersion = dataPoint["device_firmware_version"] as String?;
    final String? deviceSoftwareVersion = dataPoint["device_software_version"] as String?;
    final String? deviceLocalIdentifier = dataPoint["device_local_identifier"] as String?;
    final String? deviceUdiIdentifier = dataPoint["device_udi_identifier"] as String?;
    final String? sourceProductType = dataPoint["source_product_type"] as String?;
    final String? sourceOsVersion = dataPoint["source_os_version"] as String?;
    final String? sourceVersion = dataPoint["source_version"] as String?;

    // Set WorkoutSummary, if available.
    WorkoutSummary? workoutSummary;
    if (dataPoint["workout_type"] != null ||
        dataPoint["total_distance"] != null ||
        dataPoint["total_energy_burned"] != null ||
        dataPoint["total_steps"] != null) {
      workoutSummary = WorkoutSummary.fromHealthDataPoint(dataPoint);
    }

    var recordingMethod = dataPoint["recording_method"] as int?;

    return HealthDataPoint(
      uuid: uuid ?? "",
      value: value,
      type: dataType,
      unit: unit,
      dateFrom: from,
      dateTo: to,
      sourcePlatform: Health().platformType,
      sourceDeviceId: Health().deviceId,
      sourceId: sourceId,
      sourceName: sourceName,
      recordingMethod: RecordingMethod.fromInt(recordingMethod),
      workoutSummary: workoutSummary,
      metadata: metadata,
      deviceModel: deviceModel,
      deviceManufacturer: deviceManufacturer,
      deviceName: deviceName,
      deviceHardwareVersion: deviceHardwareVersion,
      deviceFirmwareVersion: deviceFirmwareVersion,
      deviceSoftwareVersion: deviceSoftwareVersion,
      deviceLocalIdentifier: deviceLocalIdentifier,
      deviceUdiIdentifier: deviceUdiIdentifier,
      sourceProductType: sourceProductType,
      sourceOsVersion: sourceOsVersion,
      sourceVersion: sourceVersion,
    );
  }

  @override
  String toString() =>
      """$runtimeType -
    uuid: $uuid,
    value: ${value.toString()},
    unit: ${unit.name},
    dateFrom: $dateFrom,
    dateTo: $dateTo,
    dataType: ${type.name},
    platform: $sourcePlatform,
    deviceId: $sourceDeviceId,
    sourceId: $sourceId,
    sourceName: $sourceName
    recordingMethod: $recordingMethod
    workoutSummary: $workoutSummary
    metadata: $metadata
    deviceModel: $deviceModel
    deviceManufacturer: $deviceManufacturer
    deviceName: $deviceName
    deviceHardwareVersion: $deviceHardwareVersion
    deviceFirmwareVersion: $deviceFirmwareVersion
    deviceSoftwareVersion: $deviceSoftwareVersion
    deviceLocalIdentifier: $deviceLocalIdentifier
    deviceUdiIdentifier: $deviceUdiIdentifier
    sourceProductType: $sourceProductType
    sourceOsVersion: $sourceOsVersion
    sourceVersion: $sourceVersion""";

  @override
  bool operator ==(Object other) =>
      other is HealthDataPoint &&
      uuid == other.uuid &&
      value == other.value &&
      unit == other.unit &&
      dateFrom == other.dateFrom &&
      dateTo == other.dateTo &&
      type == other.type &&
      sourcePlatform == other.sourcePlatform &&
      sourceDeviceId == other.sourceDeviceId &&
      sourceId == other.sourceId &&
      sourceName == other.sourceName &&
      recordingMethod == other.recordingMethod &&
      metadata == other.metadata &&
      deviceModel == other.deviceModel &&
      deviceManufacturer == other.deviceManufacturer &&
      deviceName == other.deviceName &&
      deviceHardwareVersion == other.deviceHardwareVersion &&
      deviceFirmwareVersion == other.deviceFirmwareVersion &&
      deviceSoftwareVersion == other.deviceSoftwareVersion &&
      deviceLocalIdentifier == other.deviceLocalIdentifier &&
      deviceUdiIdentifier == other.deviceUdiIdentifier &&
      sourceProductType == other.sourceProductType &&
      sourceOsVersion == other.sourceOsVersion &&
      sourceVersion == other.sourceVersion;

  @override
  int get hashCode => Object.hashAll([
    uuid,
    value,
    unit,
    dateFrom,
    dateTo,
    type,
    sourcePlatform,
    sourceDeviceId,
    sourceId,
    sourceName,
    metadata,
    deviceModel,
    deviceManufacturer,
    deviceName,
    deviceHardwareVersion,
    deviceFirmwareVersion,
    deviceSoftwareVersion,
    deviceLocalIdentifier,
    deviceUdiIdentifier,
    sourceProductType,
    sourceOsVersion,
    sourceVersion,
  ]);
}
