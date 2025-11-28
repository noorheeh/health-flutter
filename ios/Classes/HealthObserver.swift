import Flutter
import HealthKit

/// Manages HKObserverQuery instances to provide real-time health data updates
/// Uses EventChannel to stream updates back to Flutter when health data changes
class HealthObserver: NSObject, FlutterStreamHandler {
    private let healthStore: HKHealthStore
    private let dataTypesDict: [String: HKSampleType]
    private var eventSink: FlutterEventSink?
    private var activeObservers: [String: HKObserverQuery] = [:]
    private let observerQueue = DispatchQueue(label: "com.carp.health.observer")

    /// Initialize the health observer
    /// - Parameters:
    ///   - healthStore: The HealthKit store
    ///   - dataTypesDict: Dictionary of data types
    init(healthStore: HKHealthStore, dataTypesDict: [String: HKSampleType]) {
        self.healthStore = healthStore
        self.dataTypesDict = dataTypesDict
        super.init()
    }

    // MARK: - FlutterStreamHandler

    /// Called when Flutter starts listening to the event stream
    /// - Parameters:
    ///   - arguments: Arguments from Flutter (expected: array of dataTypeKeys to observe)
    ///   - eventSink: Callback to send events to Flutter
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events

        guard let args = arguments as? [String: Any],
              let dataTypeKeys = args["dataTypeKeys"] as? [String] else {
            return FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "Expected dataTypeKeys array in arguments",
                details: nil
            )
        }

        // Enable background delivery if requested
        let enableBackground = args["enableBackground"] as? Bool ?? false

        // Start observing the requested data types
        for dataTypeKey in dataTypeKeys {
            if let error = startObserving(dataTypeKey: dataTypeKey, enableBackground: enableBackground) {
                return error
            }
        }

        return nil
    }

    /// Called when Flutter stops listening to the event stream
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopAllObservers()
        eventSink = nil
        return nil
    }

    // MARK: - Observer Management

    /// Start observing a specific health data type
    /// - Parameters:
    ///   - dataTypeKey: The data type key to observe
    ///   - enableBackground: Whether to enable background delivery
    /// - Returns: FlutterError if the observation cannot be started
    private func startObserving(dataTypeKey: String, enableBackground: Bool) -> FlutterError? {
        guard let sampleType = dataTypesDict[dataTypeKey] else {
            return FlutterError(
                code: "INVALID_TYPE",
                message: "Invalid dataTypeKey: \(dataTypeKey)",
                details: nil
            )
        }

        // Don't create duplicate observers
        if activeObservers[dataTypeKey] != nil {
            return nil
        }

        // Create the observer query
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] query, completionHandler, error in
            guard let self = self else {
                completionHandler()
                return
            }

            if let error = error {
                self.sendEvent([
                    "type": "error",
                    "dataTypeKey": dataTypeKey,
                    "error": error.localizedDescription
                ])
                completionHandler()
                return
            }

            // Notify Flutter that new data is available
            self.sendEvent([
                "type": "update",
                "dataTypeKey": dataTypeKey,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ])

            // Call completion handler to let HealthKit know we're done processing
            completionHandler()
        }

        // Store the query
        activeObservers[dataTypeKey] = query

        // Execute the query
        healthStore.execute(query)

        // Enable background delivery if requested (iOS 8.0+)
        if enableBackground {
            let frequency = HKUpdateFrequency.immediate
            healthStore.enableBackgroundDelivery(for: sampleType, frequency: frequency) { success, error in
                if let error = error {
                    self.sendEvent([
                        "type": "background_delivery_error",
                        "dataTypeKey": dataTypeKey,
                        "error": error.localizedDescription
                    ])
                } else if success {
                    self.sendEvent([
                        "type": "background_delivery_enabled",
                        "dataTypeKey": dataTypeKey
                    ])
                }
            }
        }

        return nil
    }

    /// Stop observing a specific data type
    /// - Parameter dataTypeKey: The data type key to stop observing
    private func stopObserving(dataTypeKey: String) {
        if let query = activeObservers[dataTypeKey] {
            healthStore.stop(query)
            activeObservers.removeValue(forKey: dataTypeKey)

            // Disable background delivery
            if let sampleType = dataTypesDict[dataTypeKey] {
                healthStore.disableBackgroundDelivery(for: sampleType) { _, _ in
                    // Silently handle completion
                }
            }
        }
    }

    /// Stop all active observers
    private func stopAllObservers() {
        for dataTypeKey in activeObservers.keys {
            stopObserving(dataTypeKey: dataTypeKey)
        }
    }

    // MARK: - Event Handling

    /// Send an event to Flutter through the event sink
    /// - Parameter event: The event data to send
    private func sendEvent(_ event: [String: Any]) {
        observerQueue.async { [weak self] in
            guard let self = self, let sink = self.eventSink else { return }

            DispatchQueue.main.async {
                sink(event)
            }
        }
    }
}
