/// Battery state information for power-aware decisions
class BatteryState {
  /// Battery level percentage (0-100)
  final int level;

  /// Whether the device is currently charging
  final bool isCharging;

  /// Whether power save mode is enabled
  final bool isPowerSaveMode;

  /// Whether the app is in background
  final bool isBackgrounded;

  /// Last update timestamp
  final DateTime lastUpdate;

  const BatteryState({
    required this.level,
    required this.isCharging,
    required this.isPowerSaveMode,
    required this.isBackgrounded,
    required this.lastUpdate,
  });

  /// Create a battery state with default values for testing
  factory BatteryState.defaultState() {
    return BatteryState(
      level: 100,
      isCharging: false,
      isPowerSaveMode: false,
      isBackgrounded: false,
      lastUpdate: DateTime.now(),
    );
  }

  /// Check if battery is in critical state
  bool get isCritical => level < 10 && !isCharging;

  /// Check if battery optimizations should be applied
  bool get shouldOptimize => isPowerSaveMode || isCritical || isBackgrounded;

  @override
  String toString() => 'BatteryState(level: $level%, charging: $isCharging, '
      'powerSave: $isPowerSaveMode, background: $isBackgrounded)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatteryState &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          isCharging == other.isCharging &&
          isPowerSaveMode == other.isPowerSaveMode &&
          isBackgrounded == other.isBackgrounded;

  @override
  int get hashCode =>
      level.hashCode ^
      isCharging.hashCode ^
      isPowerSaveMode.hashCode ^
      isBackgrounded.hashCode;
}