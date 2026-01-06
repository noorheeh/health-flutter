import Flutter
import HealthKit

// MARK: - Storage Keys

private enum StorageKeys {
    static let anchorPrefix = "com.health.observer.anchor."
    static let pendingUpdates = "com.health.observer.pending"
    static let registeredTypes = "com.health.observer.types"
}

// MARK: - HealthObserver

/// Manages HKAnchoredObjectQuery instances for real-time health data updates.
/// Uses EventChannel to stream updates back to Flutter when health data changes.
/// Supports returning actual data samples with each update.
class HealthObserver: NSObject, FlutterStreamHandler {

    // MARK: - Properties

    private let healthStore: HKHealthStore
    private let dataTypesDict: [String: HKSampleType]
    private let unitDict: [String: HKUnit]
    private var eventSink: FlutterEventSink?
    private var activeQueries: [String: HKAnchoredObjectQuery] = [:]
    private let queue = DispatchQueue(label: "com.health.observer", qos: .userInitiated)

    // Configuration
    private var includeData: Bool = false

    // MARK: - Initialization

    init(healthStore: HKHealthStore, dataTypesDict: [String: HKSampleType], unitDict: [String: HKUnit] = [:]) {
        self.healthStore = healthStore
        self.dataTypesDict = dataTypesDict
        self.unitDict = unitDict
        super.init()
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events

        guard let args = arguments as? [String: Any],
              let dataTypeKeys = args["dataTypeKeys"] as? [String] else {
            return FlutterError(code: "INVALID_ARGUMENTS", message: "Expected dataTypeKeys array", details: nil)
        }

        let enableBackground = args["enableBackground"] as? Bool ?? false
        self.includeData = args["includeData"] as? Bool ?? false

        // Deliver any pending updates first
        deliverPendingUpdates()

        // Start observing each type
        for key in dataTypeKeys {
            if let error = startObserving(dataTypeKey: key, enableBackground: enableBackground) {
                return error
            }
        }

        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopAllQueries()
        eventSink = nil
        return nil
    }

    // MARK: - Query Management

    private func startObserving(dataTypeKey: String, enableBackground: Bool) -> FlutterError? {
        guard let sampleType = dataTypesDict[dataTypeKey] else {
            return FlutterError(code: "INVALID_TYPE", message: "Unknown type: \(dataTypeKey)", details: nil)
        }

        // Prevent duplicates
        guard activeQueries[dataTypeKey] == nil else { return nil }

        // Load saved anchor
        let anchor = loadAnchor(for: dataTypeKey)

        // Create anchored query - returns actual data
        let query = HKAnchoredObjectQuery(
            type: sampleType,
            predicate: nil,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, added, deleted, newAnchor, error in
            self?.handleQueryResult(
                dataTypeKey: dataTypeKey,
                added: added,
                deleted: deleted,
                newAnchor: newAnchor,
                error: error,
                isInitial: true
            )
        }

        // Handle subsequent updates
        query.updateHandler = { [weak self] query, added, deleted, newAnchor, error in
            self?.handleQueryResult(
                dataTypeKey: dataTypeKey,
                added: added,
                deleted: deleted,
                newAnchor: newAnchor,
                error: error,
                isInitial: false
            )
        }

        activeQueries[dataTypeKey] = query
        healthStore.execute(query)

        // Enable background delivery
        if enableBackground {
            enableBackgroundDelivery(for: sampleType, dataTypeKey: dataTypeKey)
        }

        return nil
    }

    private func handleQueryResult(
        dataTypeKey: String,
        added: [HKSample]?,
        deleted: [HKDeletedObject]?,
        newAnchor: HKQueryAnchor?,
        error: Error?,
        isInitial: Bool
    ) {
        // Save new anchor
        if let anchor = newAnchor {
            saveAnchor(anchor, for: dataTypeKey)
        }

        // Handle error
        if let error = error {
            sendEvent(type: "error", dataTypeKey: dataTypeKey, error: error.localizedDescription)
            return
        }

        // Skip initial fetch if no data
        let addedCount = added?.count ?? 0
        let deletedCount = deleted?.count ?? 0

        if isInitial && addedCount == 0 && deletedCount == 0 {
            return
        }

        // Build event
        var event: [String: Any] = [
            "type": "update",
            "dataTypeKey": dataTypeKey,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "addedCount": addedCount,
            "deletedCount": deletedCount,
        ]

        // Include actual data if requested
        if includeData {
            if let samples = added, !samples.isEmpty {
                event["addedSamples"] = samples.compactMap { serializeSample($0, dataTypeKey: dataTypeKey) }
            }
            if let deletedObjects = deleted, !deletedObjects.isEmpty {
                event["deletedUUIDs"] = deletedObjects.map { $0.uuid.uuidString }
            }
        }

        sendEvent(event)
    }

    private func stopObserving(dataTypeKey: String) {
        guard let query = activeQueries.removeValue(forKey: dataTypeKey) else { return }
        healthStore.stop(query)

        if let sampleType = dataTypesDict[dataTypeKey] {
            healthStore.disableBackgroundDelivery(for: sampleType) { _, _ in }
        }
    }

    private func stopAllQueries() {
        for key in activeQueries.keys {
            stopObserving(dataTypeKey: key)
        }
    }

    // MARK: - Background Delivery

    private func enableBackgroundDelivery(for sampleType: HKSampleType, dataTypeKey: String) {
        healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { [weak self] success, error in
            if let error = error {
                self?.sendEvent(type: "background_delivery_error", dataTypeKey: dataTypeKey, error: error.localizedDescription)
            } else if success {
                self?.sendEvent(type: "background_delivery_enabled", dataTypeKey: dataTypeKey)
            }
        }
    }

    // MARK: - Anchor Persistence

    private func loadAnchor(for dataTypeKey: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: StorageKeys.anchorPrefix + dataTypeKey) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor, for dataTypeKey: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            return
        }
        UserDefaults.standard.set(data, forKey: StorageKeys.anchorPrefix + dataTypeKey)
    }

    // MARK: - Pending Updates

    private func deliverPendingUpdates() {
        guard let pending = UserDefaults.standard.array(forKey: StorageKeys.pendingUpdates) as? [[String: Any]] else {
            return
        }

        for update in pending {
            sendEvent(update)
        }

        UserDefaults.standard.removeObject(forKey: StorageKeys.pendingUpdates)
    }

    static func savePendingUpdate(_ update: [String: Any]) {
        var pending = UserDefaults.standard.array(forKey: StorageKeys.pendingUpdates) as? [[String: Any]] ?? []
        pending.append(update)
        UserDefaults.standard.set(pending, forKey: StorageKeys.pendingUpdates)
    }

    // MARK: - Sample Serialization

    private func serializeSample(_ sample: HKSample, dataTypeKey: String) -> [String: Any]? {
        var data: [String: Any] = [
            "uuid": sample.uuid.uuidString,
            "date_from": Int(sample.startDate.timeIntervalSince1970 * 1000),
            "date_to": Int(sample.endDate.timeIntervalSince1970 * 1000),
            "source_id": sample.sourceRevision.source.bundleIdentifier,
            "source_name": sample.sourceRevision.source.name,
        ]

        // Handle quantity samples
        if let quantitySample = sample as? HKQuantitySample {
            if let unit = getUnit(for: dataTypeKey) {
                data["value"] = quantitySample.quantity.doubleValue(for: unit)
                data["unit"] = unit.unitString
            }
        }

        // Handle category samples
        if let categorySample = sample as? HKCategorySample {
            data["value"] = categorySample.value
        }

        // Handle workouts
        if let workout = sample as? HKWorkout {
            data["workout_type"] = workout.workoutActivityType.rawValue
            data["duration"] = workout.duration
            if let energy = workout.totalEnergyBurned {
                data["total_energy"] = energy.doubleValue(for: .kilocalorie())
            }
            if let distance = workout.totalDistance {
                data["total_distance"] = distance.doubleValue(for: .meter())
            }
        }

        return data
    }

    private func getUnit(for dataTypeKey: String) -> HKUnit? {
        // Try from unitDict first
        if let unit = unitDict[dataTypeKey] {
            return unit
        }

        // Common defaults
        let defaults: [String: HKUnit] = [
            "STEPS": .count(),
            "HEART_RATE": HKUnit(from: "count/min"),
            "WEIGHT": .gramUnit(with: .kilo),
            "HEIGHT": .meter(),
            "BLOOD_OXYGEN": .percent(),
            "BLOOD_GLUCOSE": HKUnit(from: "mg/dL"),
            "BODY_TEMPERATURE": .degreeCelsius(),
            "ACTIVE_ENERGY_BURNED": .kilocalorie(),
            "BASAL_ENERGY_BURNED": .kilocalorie(),
            "DISTANCE_WALKING_RUNNING": .meter(),
            "FLIGHTS_CLIMBED": .count(),
        ]

        return defaults[dataTypeKey]
    }

    // MARK: - Event Sending

    private func sendEvent(_ event: [String: Any]) {
        queue.async { [weak self] in
            DispatchQueue.main.async {
                self?.eventSink?(event)
            }
        }
    }

    private func sendEvent(type: String, dataTypeKey: String, error: String? = nil) {
        var event: [String: Any] = [
            "type": type,
            "dataTypeKey": dataTypeKey,
        ]
        if let error = error {
            event["error"] = error
        }
        sendEvent(event)
    }
}

// MARK: - HealthBackgroundHandler

/// Static handler for persistent background health observations.
/// Call from AppDelegate to register observers at app launch.
public class HealthBackgroundHandler {

    private static let healthStore = HKHealthStore()
    private static var backgroundQueries: [String: HKObserverQuery] = [:]

    /// Register persistent background observers for the given health data types.
    /// Call this from AppDelegate.didFinishLaunchingWithOptions.
    ///
    /// - Parameter typeIdentifiers: Array of HealthKit type identifier strings (e.g., "HKQuantityTypeIdentifierStepCount")
    public static func registerPersistentObservers(typeIdentifiers: [String]? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Load saved types if none provided
        let types = typeIdentifiers ?? loadRegisteredTypes()
        guard !types.isEmpty else { return }

        for identifier in types {
            registerObserver(for: identifier)
        }
    }

    /// Register types that should persist across app launches.
    /// - Parameter types: Array of type keys (e.g., ["STEPS", "HEART_RATE"])
    public static func saveRegisteredTypes(_ types: [String]) {
        UserDefaults.standard.set(types, forKey: StorageKeys.registeredTypes)
    }

    /// Get pending updates that occurred while the app was terminated.
    public static func getPendingUpdates() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: StorageKeys.pendingUpdates) as? [[String: Any]] ?? []
    }

    /// Clear all pending updates.
    public static func clearPendingUpdates() {
        UserDefaults.standard.removeObject(forKey: StorageKeys.pendingUpdates)
    }

    // MARK: - Private

    private static func loadRegisteredTypes() -> [String] {
        return UserDefaults.standard.stringArray(forKey: StorageKeys.registeredTypes) ?? []
    }

    private static func registerObserver(for typeKey: String) {
        guard let sampleType = getSampleType(for: typeKey) else { return }
        guard backgroundQueries[typeKey] == nil else { return }

        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, error in
            if error == nil {
                // Save pending update for Flutter to read later
                let update: [String: Any] = [
                    "type": "update",
                    "dataTypeKey": typeKey,
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                    "isBackgroundUpdate": true,
                ]
                HealthObserver.savePendingUpdate(update)
            }
            completionHandler()
        }

        backgroundQueries[typeKey] = query
        healthStore.execute(query)

        // Enable background delivery
        healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { _, _ in }
    }

    private static func getSampleType(for typeKey: String) -> HKSampleType? {
        let mapping: [String: HKSampleType] = [
            "STEPS": HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            "HEART_RATE": HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            "WEIGHT": HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            "HEIGHT": HKQuantityType.quantityType(forIdentifier: .height)!,
            "BLOOD_OXYGEN": HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!,
            "BLOOD_GLUCOSE": HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!,
            "ACTIVE_ENERGY_BURNED": HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            "DISTANCE_WALKING_RUNNING": HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            "FLIGHTS_CLIMBED": HKQuantityType.quantityType(forIdentifier: .flightsClimbed)!,
            "SLEEP_ASLEEP": HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
            "WORKOUT": HKWorkoutType.workoutType(),
        ]
        return mapping[typeKey]
    }
}
