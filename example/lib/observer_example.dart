import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:health/health.dart';

/// Example app demonstrating the Health Observer feature (iOS only).
///
/// This shows how to:
/// - Observe real-time health data changes
/// - Get actual data with updates (no separate fetch needed)
/// - Handle background updates
/// - Detect backdated data
/// - Handle pending updates from terminated state
void main() => runApp(const ObserverExampleApp());

class ObserverExampleApp extends StatelessWidget {
  const ObserverExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Observer Example',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const ObserverExamplePage(),
    );
  }
}

class ObserverExamplePage extends StatefulWidget {
  const ObserverExamplePage({super.key});

  @override
  State<ObserverExamplePage> createState() => _ObserverExamplePageState();
}

class _ObserverExamplePageState extends State<ObserverExamplePage> {
  final Health _health = Health();

  // Observer state
  StreamSubscription<HealthObserverUpdate>? _subscription;
  bool _isObserving = false;
  bool _includeData = true;
  bool _enableBackground = false;

  // Log entries
  final List<_LogEntry> _logs = [];

  // Types to observe
  final List<HealthDataType> _observedTypes = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
  ];

  @override
  void initState() {
    super.initState();
    print('[OBSERVER] initState() - App starting');
    print('[OBSERVER] Platform.isIOS: ${Platform.isIOS}');
    _health.configure();
    print('[OBSERVER] Health configured, checking pending updates...');
    _checkPendingUpdates();
  }

  @override
  void dispose() {
    _stopObserving();
    super.dispose();
  }

  // MARK: - Observer Methods

  Future<void> _requestPermissions() async {
    print('[OBSERVER] _requestPermissions() called');
    _addLog('Requesting permissions...');

    try {
      print('[OBSERVER] Calling _health.requestAuthorization for types: $_observedTypes');
      final authorized = await _health.requestAuthorization(
        _observedTypes,
        permissions: _observedTypes.map((_) => HealthDataAccess.READ_WRITE).toList(),
      );

      print('[OBSERVER] Authorization result: $authorized');
      _addLog(authorized ? 'Permissions granted' : 'Permissions denied', isError: !authorized);
    } catch (e) {
      print('[OBSERVER] Permission error: $e');
      _addLog('Permission error: $e', isError: true);
    }
  }

  void _startObserving() {
    print('[OBSERVER] _startObserving() called');
    if (!Platform.isIOS) {
      print('[OBSERVER] Not iOS - aborting');
      _addLog('Observer only available on iOS', isError: true);
      return;
    }

    print('[OBSERVER] Starting observer with types: $_observedTypes');
    print('[OBSERVER] includeData: $_includeData, enableBackground: $_enableBackground');
    _addLog('Starting observer (includeData: $_includeData, background: $_enableBackground)');

    _subscription = _health.observeHealthData(
      types: _observedTypes,
      includeData: _includeData,
      enableBackground: _enableBackground,
    ).listen(
      _handleUpdate,
      onError: (error) {
        print('[OBSERVER] Stream error: $error');
        _addLog('Stream error: $error', isError: true);
      },
    );

    print('[OBSERVER] Observer started, subscription created');
    setState(() => _isObserving = true);
  }

  void _stopObserving() {
    print('[OBSERVER] _stopObserving() called');
    _subscription?.cancel();
    _subscription = null;
    _health.stopObservingHealthData();

    if (_isObserving) {
      print('[OBSERVER] Observer stopped');
      _addLog('Observer stopped');
    }

    setState(() => _isObserving = false);
  }

  void _handleUpdate(HealthObserverUpdate update) {
    print('[OBSERVER] _handleUpdate() received event type: ${update.type}');
    print('[OBSERVER] Update details: dataType=${update.dataType}, error=${update.error}');

    switch (update.type) {
      case HealthObserverEventType.update:
        print('[OBSERVER] -> Handling data update');
        _handleDataUpdate(update);
        break;

      case HealthObserverEventType.error:
        print('[OBSERVER] -> Observer error: ${update.error}');
        _addLog('Observer error: ${update.error}', isError: true);
        break;

      case HealthObserverEventType.backgroundDeliveryEnabled:
        print('[OBSERVER] -> Background enabled for ${update.dataType?.name}');
        _addLog('Background enabled for ${update.dataType?.name}');
        break;

      case HealthObserverEventType.backgroundDeliveryError:
        print('[OBSERVER] -> Background error: ${update.error}');
        _addLog('Background error: ${update.error}', isError: true);
        break;
    }
  }

  void _handleDataUpdate(HealthObserverUpdate update) {
    print('[OBSERVER] _handleDataUpdate() for type: ${update.dataType?.name}');
    print('[OBSERVER] addedCount: ${update.addedCount}, deletedCount: ${update.deletedCount}');
    print('[OBSERVER] isBackgroundUpdate: ${update.isBackgroundUpdate}');
    print('[OBSERVER] addedSamples: ${update.addedSamples?.length ?? 0} samples');

    final buffer = StringBuffer();
    buffer.writeln('UPDATE: ${update.dataType?.name}');
    buffer.writeln('  Added: ${update.addedCount ?? 0}');
    buffer.writeln('  Deleted: ${update.deletedCount ?? 0}');

    if (update.isBackgroundUpdate) {
      buffer.writeln('  (Background update)');
    }

    // Check for backdated data
    if (update.isBackdated()) {
      print('[OBSERVER] Contains backdated data!');
      buffer.writeln('  (Contains backdated data)');
    }

    // Show sample details if includeData was true
    if (update.addedSamples != null && update.addedSamples!.isNotEmpty) {
      print('[OBSERVER] Sample data received:');
      buffer.writeln('  Samples:');
      for (final sample in update.addedSamples!.take(3)) {
        print('[OBSERVER]   Sample: $sample');
        final value = sample['value'];
        final unit = sample['unit'] ?? '';
        final dateFrom = DateTime.fromMillisecondsSinceEpoch(sample['date_from'] as int);
        final age = DateTime.now().difference(dateFrom);

        buffer.writeln('    - $value $unit');
        buffer.writeln('      Time: ${_formatDateTime(dateFrom)}');
        if (age.inHours > 1) {
          buffer.writeln('      (${age.inHours}h ago - backdated)');
        }
      }
      if (update.addedSamples!.length > 3) {
        buffer.writeln('    ... and ${update.addedSamples!.length - 3} more');
      }
    }

    _addLog(buffer.toString().trim());
  }

  // MARK: - Background & Pending Updates

  Future<void> _registerBackgroundTypes() async {
    print('[OBSERVER] _registerBackgroundTypes() called');
    _addLog('Registering background types...');

    final success = await _health.registerBackgroundTypes(types: _observedTypes);
    print('[OBSERVER] registerBackgroundTypes result: $success');
    _addLog(
      success ? 'Background types registered' : 'Failed to register background types',
      isError: !success,
    );
  }

  Future<void> _checkPendingUpdates() async {
    print('[OBSERVER] _checkPendingUpdates() called');
    if (!Platform.isIOS) {
      print('[OBSERVER] Not iOS - skipping pending updates check');
      return;
    }

    final pending = await _health.getPendingBackgroundUpdates();
    print('[OBSERVER] Found ${pending.length} pending updates');
    if (pending.isNotEmpty) {
      _addLog('Found ${pending.length} pending updates from background');

      for (final update in pending) {
        print('[OBSERVER] Pending update: ${update.dataType?.name} at ${update.timestamp}');
        _addLog('  Pending: ${update.dataType?.name} at ${_formatTimestamp(update.timestamp)}');
      }

      await _health.clearPendingUpdates();
      print('[OBSERVER] Pending updates cleared');
      _addLog('Pending updates cleared');
    }
  }

  // MARK: - Test Data

  Future<void> _addTestData() async {
    print('[OBSERVER] _addTestData() called');
    _addLog('Adding test data...');

    try {
      final now = DateTime.now();
      print('[OBSERVER] Writing 100 STEPS from ${now.subtract(const Duration(minutes: 5))} to $now');
      final success = await _health.writeHealthData(
        value: 100,
        type: HealthDataType.STEPS,
        startTime: now.subtract(const Duration(minutes: 5)),
        endTime: now,
        recordingMethod: RecordingMethod.manual,
      );

      print('[OBSERVER] writeHealthData result: $success');
      _addLog(success ? 'Test data added' : 'Failed to add test data', isError: !success);
    } catch (e) {
      print('[OBSERVER] Error adding data: $e');
      _addLog('Error adding data: $e', isError: true);
    }
  }

  Future<void> _addBackdatedData() async {
    print('[OBSERVER] _addBackdatedData() called');
    _addLog('Adding backdated data (2 hours ago)...');

    try {
      final twoHoursAgo = DateTime.now().subtract(const Duration(hours: 2));
      print('[OBSERVER] Writing 500 STEPS backdated to $twoHoursAgo');
      final success = await _health.writeHealthData(
        value: 500,
        type: HealthDataType.STEPS,
        startTime: twoHoursAgo.subtract(const Duration(minutes: 30)),
        endTime: twoHoursAgo,
        recordingMethod: RecordingMethod.manual,
      );

      print('[OBSERVER] writeHealthData (backdated) result: $success');
      _addLog(
        success ? 'Backdated data added - observer should detect it' : 'Failed to add backdated data',
        isError: !success,
      );
    } catch (e) {
      print('[OBSERVER] Error adding backdated data: $e');
      _addLog('Error adding backdated data: $e', isError: true);
    }
  }

  // MARK: - Helpers

  void _addLog(String message, {bool isError = false}) {
    setState(() {
      _logs.insert(0, _LogEntry(message: message, isError: isError, time: DateTime.now()));
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  void _clearLogs() {
    setState(() => _logs.clear());
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null) return 'unknown';
    return _formatDateTime(DateTime.fromMillisecondsSinceEpoch(timestamp));
  }

  // MARK: - UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Observer'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clearLogs),
        ],
      ),
      body: Column(
        children: [
          _buildControls(),
          const Divider(height: 1),
          _buildOptions(),
          const Divider(height: 1),
          Expanded(child: _buildLogList()),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ElevatedButton(
            onPressed: _requestPermissions,
            child: const Text('Permissions'),
          ),
          ElevatedButton(
            onPressed: _isObserving ? _stopObserving : _startObserving,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isObserving ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(_isObserving ? 'Stop' : 'Start'),
          ),
          ElevatedButton(
            onPressed: _addTestData,
            child: const Text('Add Data'),
          ),
          ElevatedButton(
            onPressed: _addBackdatedData,
            child: const Text('Add Backdated'),
          ),
          ElevatedButton(
            onPressed: _registerBackgroundTypes,
            child: const Text('Register BG'),
          ),
          ElevatedButton(
            onPressed: _checkPendingUpdates,
            child: const Text('Check Pending'),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: CheckboxListTile(
              title: const Text('Include Data'),
              subtitle: const Text('Get samples with updates'),
              value: _includeData,
              dense: true,
              onChanged: _isObserving
                  ? null
                  : (v) => setState(() => _includeData = v ?? false),
            ),
          ),
          Expanded(
            child: CheckboxListTile(
              title: const Text('Background'),
              subtitle: const Text('Receive while backgrounded'),
              value: _enableBackground,
              dense: true,
              onChanged: _isObserving
                  ? null
                  : (v) => setState(() => _enableBackground = v ?? false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monitor_heart_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              Platform.isIOS ? 'Press Start to begin observing' : 'Observer only available on iOS',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: log.isError ? Colors.red.withValues(alpha: 0.1) : null,
            border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatDateTime(log.time),
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
              const SizedBox(height: 2),
              Text(
                log.message,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: log.isError ? Colors.red[700] : Colors.black87,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogEntry {
  final String message;
  final bool isError;
  final DateTime time;

  _LogEntry({required this.message, required this.isError, required this.time});
}
