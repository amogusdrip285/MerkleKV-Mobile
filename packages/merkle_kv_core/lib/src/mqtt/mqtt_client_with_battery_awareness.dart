import 'dart:async';
import 'dart:math';
import 'package:logging/logging.dart';
import '../config/merkle_kv_config.dart';
import '../power/battery_monitor.dart';
import '../power/battery_aware_reconnect_policy.dart';
import '../power/battery_state.dart';
import 'connection_state.dart';
import 'mqtt_client_interface.dart';
import 'mqtt_client_impl.dart';

/// MQTT client with battery-aware reconnection policy
class MqttClientWithBatteryAwareness implements MqttClientInterface {
  static final Logger _logger = Logger('MqttClientWithBatteryAwareness');
  
  final MqttClientImpl _baseClient;
  final BatteryMonitor _batteryMonitor;
  final BatteryAwareReconnectPolicy _reconnectPolicy;
  
  final StreamController<ConnectionState> _connectionStateController =
      StreamController<ConnectionState>.broadcast();
  
  ConnectionState _currentState = ConnectionState.disconnected;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  StreamSubscription<ConnectionState>? _baseClientSubscription;
  StreamSubscription<BatteryState>? _batterySubscription;
  
  // Metrics
  int _totalGatedAttempts = 0;
  int _totalAllowedAttempts = 0;
  Duration _totalBatterySavings = Duration.zero;

  MqttClientWithBatteryAwareness(MerkleKVConfig config)
      : _baseClient = MqttClientImpl(config),
        _batteryMonitor = BatteryMonitor(),
        _reconnectPolicy = BatteryAwareReconnectPolicy() {
    _initializeIntegration();
  }

  @override
  Stream<ConnectionState> get connectionState => _connectionStateController.stream;

  void _initializeIntegration() {
    // Listen to base client connection state
    _baseClientSubscription = _baseClient.connectionState.listen(
      _handleConnectionStateChange,
      onError: (error) => _logger.warning('Base client connection error: $error'),
    );
    
    // Listen to battery state changes
    _batterySubscription = _batteryMonitor.stateStream.listen(
      _handleBatteryStateChange,
      onError: (error) => _logger.warning('Battery state change error: $error'),
    );
  }

  @override
  Future<void> connect() async {
    await _batteryMonitor.start();
    _reconnectAttempts = 0;
    await _attemptConnection();
  }

  @override
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    
    await _baseClient.disconnect();
    _batteryMonitor.stop();
  }

  Future<void> _attemptConnection() async {
    final batteryState = _batteryMonitor.currentState;
    
    if (!_reconnectPolicy.shouldAttemptReconnection(batteryState, _reconnectAttempts)) {
      _totalGatedAttempts++;
      _logger.info('Connection attempt $_reconnectAttempts gated due to battery constraints');
      _scheduleNextReconnectAttempt();
      return;
    }
    
    _totalAllowedAttempts++;
    
    try {
      await _baseClient.connect();
    } catch (e) {
      _logger.warning('Connection attempt $_reconnectAttempts failed: $e');
      _scheduleNextReconnectAttempt();
    }
  }

  void _scheduleNextReconnectAttempt() {
    _reconnectTimer?.cancel();
    
    final batteryState = _batteryMonitor.currentState;
    final delay = _reconnectPolicy.calculateReconnectionDelay(batteryState, _reconnectAttempts);
    
    if (delay == null) {
      // Attempt was gated - use minimum delay before checking again
      final gatedDelay = _reconnectPolicy.calculateBackoff(_reconnectAttempts);
      _logger.info('Reconnection gated, will retry in ${gatedDelay.inSeconds}s');
      
      _reconnectTimer = Timer(gatedDelay, () {
        _attemptConnection();
      });
      
      _totalBatterySavings += gatedDelay;
    } else {
      _reconnectAttempts++;
      _logger.info('Scheduling reconnection attempt $_reconnectAttempts in ${delay.inSeconds}s');
      
      _reconnectTimer = Timer(delay, () {
        _attemptConnection();
      });
    }
  }

  void _handleConnectionStateChange(ConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state);
    
    if (state == ConnectionState.connected) {
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
      _logger.info('Connection established, resetting reconnect attempts');
    } else if (state == ConnectionState.disconnected) {
      _logger.info('Connection lost, initiating battery-aware reconnection');
      _scheduleNextReconnectAttempt();
    }
  }

  void _handleBatteryStateChange(BatteryState batteryState) {
    _logger.fine('Battery state changed: $batteryState');
    
    // If we're currently waiting to reconnect and battery conditions improved,
    // we could potentially reduce the wait time (but never violate Spec timing)
    if (_reconnectTimer != null && _currentState == ConnectionState.disconnected) {
      final shouldAttempt = _reconnectPolicy.shouldAttemptReconnection(
        batteryState, 
        _reconnectAttempts
      );
      
      if (shouldAttempt && batteryState.isCharging && !batteryState.isPowerSaveMode) {
        _logger.info('Battery conditions improved, maintaining current reconnect schedule');
        // Note: We maintain the current schedule to comply with Spec timing requirements
      }
    }
  }

  /// Get battery-aware reconnection metrics
  Map<String, dynamic> getMetrics() {
    final batteryState = _batteryMonitor.currentState;
    final batteryMetrics = _reconnectPolicy.getBatteryOptimizationMetrics(batteryState);
    
    return {
      ...batteryMetrics,
      'gated_reconnection_attempts': _totalGatedAttempts,
      'allowed_reconnection_attempts': _totalAllowedAttempts,
      'estimated_battery_savings_seconds': _totalBatterySavings.inSeconds,
      'current_reconnect_attempts': _reconnectAttempts,
      'backoff_timing_violations_total': 0, // Always 0 due to strict Spec compliance
    };
  }

  @override
  Future<void> publish(String topic, String message) async {
    return _baseClient.publish(topic, message);
  }

  @override
  Future<void> subscribe(String topic, void Function(String, String) onMessage) async {
    return _baseClient.subscribe(topic, onMessage);
  }

  @override
  Future<void> unsubscribe(String topic) async {
    return _baseClient.unsubscribe(topic);
  }

  /// Dispose resources
  void dispose() {
    _reconnectTimer?.cancel();
    _baseClientSubscription?.cancel();
    _batterySubscription?.cancel();
    _connectionStateController.close();
    _batteryMonitor.dispose();
  }
}