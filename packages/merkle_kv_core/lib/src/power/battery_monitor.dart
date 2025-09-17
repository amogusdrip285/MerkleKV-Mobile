import 'dart:async';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:logging/logging.dart';
import 'battery_state.dart';

/// Monitors device battery state for power-aware reconnection decisions
class BatteryMonitor {
  static final Logger _logger = Logger('BatteryMonitor');
  
  final Battery _battery = Battery();
  final StreamController<BatteryState> _stateController = 
      StreamController<BatteryState>.broadcast();
  
  BatteryState _currentState = BatteryState.defaultState();
  Timer? _monitoringTimer;
  StreamSubscription<BatteryState>? _batterySubscription;
  
  /// Stream of battery state changes
  Stream<BatteryState> get stateStream => _stateController.stream;
  
  /// Current battery state
  BatteryState get currentState => _currentState;

  /// Start monitoring battery state
  Future<void> start() async {
    try {
      // Get initial battery state
      await _updateBatteryState();
      
      // Set up periodic monitoring (every 30 seconds)
      _monitoringTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _updateBatteryState(),
      );
      
      // Listen to battery state changes
      _batterySubscription = _battery.onBatteryStateChanged.listen(
        (BatteryState state) => _updateBatteryState(),
        onError: (error) {
          _logger.warning('Battery state change error: $error');
        },
      );
      
      _logger.info('Battery monitoring started');
    } catch (e) {
      _logger.severe('Failed to start battery monitoring: $e');
      // Use default state if battery monitoring fails
    }
  }

  /// Stop monitoring battery state
  void stop() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    
    _batterySubscription?.cancel();
    _batterySubscription = null;
    
    _logger.info('Battery monitoring stopped');
  }

  /// Update battery state from platform
  Future<void> _updateBatteryState() async {
    try {
      final level = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;
      final isCharging = batteryState == BatteryState.charging ||
                        batteryState == BatteryState.full;
      
      // Detect power save mode (platform-specific)
      final isPowerSaveMode = await _detectPowerSaveMode();
      
      // Detect background state (simplified - in real app this would use AppLifecycleState)
      final isBackgrounded = false; // TODO: Implement via AppLifecycleState
      
      final newState = BatteryState(
        level: level,
        isCharging: isCharging,
        isPowerSaveMode: isPowerSaveMode,
        isBackgrounded: isBackgrounded,
        lastUpdate: DateTime.now(),
      );
      
      if (newState != _currentState) {
        _currentState = newState;
        _stateController.add(_currentState);
        _logger.fine('Battery state updated: $_currentState');
      }
    } catch (e) {
      _logger.warning('Failed to update battery state: $e');
    }
  }

  /// Detect power save mode (platform-specific implementation)
  Future<bool> _detectPowerSaveMode() async {
    try {
      // On Android, we could check power manager state
      // On iOS, we could check NSProcessInfo.processInfo.isLowPowerModeEnabled
      // For now, return false as this requires platform channels
      return false;
    } catch (e) {
      _logger.fine('Could not detect power save mode: $e');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    stop();
    _stateController.close();
  }
}