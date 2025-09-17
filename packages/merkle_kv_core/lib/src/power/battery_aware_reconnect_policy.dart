import 'dart:math';
import 'package:logging/logging.dart';
import 'battery_state.dart';

/// Battery-aware reconnection policy that adapts to mobile power constraints
/// while strictly adhering to Locked Spec backoff timing requirements.
class BatteryAwareReconnectPolicy {
  static final Logger _logger = Logger('BatteryAwareReconnectPolicy');
  
  final Random _random = Random();
  
  /// Maximum backoff delay per Locked Spec (32 seconds)
  static const Duration maxBackoffDelay = Duration(seconds: 32);
  
  /// Base backoff delay per Locked Spec (1 second)
  static const Duration baseBackoffDelay = Duration(seconds: 1);
  
  /// Backoff multiplier per Locked Spec (factor of 2)
  static const double backoffMultiplier = 2.0;
  
  /// Jitter range per Locked Spec (±20%)
  static const double jitterRange = 0.4;

  /// Calculate backoff delay strictly following Locked Spec timing
  /// 
  /// Backoff progression: 1s → 2s → 4s → 8s → 16s → 32s (max)
  /// With ±20% jitter applied to prevent thundering herd
  Duration calculateBackoff(int attempt) {
    // Ensure attempt is at least 1 for proper progression  
    final adjustedAttempt = max(1, attempt);
    
    // Calculate base delay: min(32s, 2^(attempt-1) seconds) for 1-based indexing
    final exponent = adjustedAttempt - 1;
    final baseSeconds = min(32, pow(2, exponent).toInt());
    final baseDelay = Duration(seconds: baseSeconds);
    
    // Apply ±20% jitter
    final jitter = (_random.nextDouble() - 0.5) * jitterRange;
    final jitteredMs = (baseDelay.inMilliseconds * (1.0 + jitter)).round();
    
    final result = Duration(milliseconds: jitteredMs);
    
    _logger.fine('Calculated backoff for attempt $attempt: ${result.inSeconds}s '
        '(base: ${baseDelay.inSeconds}s, jitter: ${(jitter * 100).toStringAsFixed(1)}%)');
    
    return result;
  }

  /// Determine if a reconnection attempt should be made based on battery state
  /// 
  /// This affects GATING (whether to attempt) but never timing (which follows Spec)
  bool shouldAttemptReconnection(BatteryState batteryState, int attempt) {
    // Always allow first few attempts regardless of battery state
    if (attempt <= 1) {
      _logger.fine('Allowing attempt $attempt (initial attempts always allowed)');
      return true;
    }

    // Power save mode gating - reduce attempts after 3 failures
    if (batteryState.isPowerSaveMode && attempt > 3) {
      _logger.info('Gating reconnection attempt $attempt due to power save mode');
      return false;
    }

    // Critical battery gating - reduce attempts when <10% and not charging
    if (batteryState.isCritical && attempt > 2) {
      _logger.info('Gating reconnection attempt $attempt due to critical battery '
          '(${batteryState.level}%, charging: ${batteryState.isCharging})');
      return false;
    }

    // Background mode gating - reduce attempt frequency when backgrounded
    if (batteryState.isBackgrounded && attempt > 5) {
      _logger.info('Gating reconnection attempt $attempt due to background mode');
      return false;
    }

    _logger.fine('Allowing reconnection attempt $attempt '
        '(battery: ${batteryState.level}%, charging: ${batteryState.isCharging}, '
        'powerSave: ${batteryState.isPowerSaveMode}, background: ${batteryState.isBackgrounded})');
    
    return true;
  }

  /// Calculate the next reconnection delay considering both Spec timing and battery gating
  /// 
  /// Returns null if the attempt should be gated (blocked)
  Duration? calculateReconnectionDelay(BatteryState batteryState, int attempt) {
    // Check if attempt should be gated
    if (!shouldAttemptReconnection(batteryState, attempt)) {
      return null; // Gated - no delay provided
    }
    
    // Calculate standard Spec-compliant backoff timing
    return calculateBackoff(attempt);
  }

  /// Get battery usage optimization recommendations
  Map<String, dynamic> getBatteryOptimizationMetrics(BatteryState batteryState) {
    return {
      'battery_level_percent': batteryState.level,
      'battery_charging_status': batteryState.isCharging,
      'power_save_mode_active': batteryState.isPowerSaveMode,
      'background_mode_active': batteryState.isBackgrounded,
      'should_optimize': batteryState.shouldOptimize,
      'is_critical': batteryState.isCritical,
      'last_update': batteryState.lastUpdate.toIso8601String(),
    };
  }
}