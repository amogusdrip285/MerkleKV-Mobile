import 'package:test/test.dart';
import 'package:merkle_kv_core/src/power/battery_aware_reconnect_policy.dart';
import 'package:merkle_kv_core/src/power/battery_state.dart';

void main() {
  group('BatteryAwareReconnectPolicy', () {
    late BatteryAwareReconnectPolicy policy;

    setUp(() {
      policy = BatteryAwareReconnectPolicy();
    });

    group('calculateBackoff', () {
      test('follows Locked Spec progression: 1s → 2s → 4s → 8s → 16s → 32s', () {
        final expectedProgression = [1, 2, 4, 8, 16, 32, 32, 32]; // 32s is max
        
        // Use 1-based indexing for attempts
        for (int i = 1; i <= expectedProgression.length; i++) {
          final backoff = policy.calculateBackoff(i);
          final expectedBase = expectedProgression[i - 1]; // Adjust for 0-based array
          
          // Allow for ±20% jitter
          final minExpected = (expectedBase * 0.8).round();
          final maxExpected = (expectedBase * 1.2).round();
          
          expect(
            backoff.inSeconds,
            inInclusiveRange(minExpected, maxExpected),
            reason: 'Attempt $i should be ${expectedBase}s ±20% jitter',
          );
        }
      });

      test('never exceeds 32 seconds maximum', () {
        // Start from attempt 1 instead of 0
        for (int attempt = 1; attempt <= 20; attempt++) {
          final backoff = policy.calculateBackoff(attempt);
          expect(
            backoff.inSeconds,
            lessThanOrEqualTo(32 * 1.2), // Account for +20% jitter
            reason: 'Attempt $attempt exceeded 32s + jitter limit',
          );
        }
      });

      test('applies ±20% jitter correctly', () {
        final backoffs = <Duration>[];
        
        // Generate multiple backoffs for the same attempt
        for (int i = 0; i < 100; i++) {
          backoffs.add(policy.calculateBackoff(4)); // 8s base (attempt 4)
        }
        
        // Check that we see variation (jitter working)
        final uniqueValues = backoffs.map((d) => d.inMilliseconds).toSet();
        expect(uniqueValues.length, greaterThan(1), 
            reason: 'Jitter should produce variation in backoff values');
        
        // All values should be within ±20% of 8s
        for (final backoff in backoffs) {
          expect(backoff.inMilliseconds, inInclusiveRange(6400, 9600)); // 8s ±20%
        }
      });
    });

    group('shouldAttemptReconnection', () {
      test('always allows first two attempts regardless of battery state', () {
        final criticalBattery = BatteryState(
          level: 5,
          isCharging: false,
          isPowerSaveMode: true,
          isBackgrounded: true,
          lastUpdate: DateTime.now(),
        );

        expect(policy.shouldAttemptReconnection(criticalBattery, 0), true);
        expect(policy.shouldAttemptReconnection(criticalBattery, 1), true);
      });

      test('gates attempts in power save mode after 3 failures', () {
        final powerSaveState = BatteryState(
          level: 50,
          isCharging: false,
          isPowerSaveMode: true,
          isBackgrounded: false,
          lastUpdate: DateTime.now(),
        );

        expect(policy.shouldAttemptReconnection(powerSaveState, 2), true);
        expect(policy.shouldAttemptReconnection(powerSaveState, 3), true);
        expect(policy.shouldAttemptReconnection(powerSaveState, 4), false);
        expect(policy.shouldAttemptReconnection(powerSaveState, 5), false);
      });

      test('gates attempts on critical battery after 2 failures', () {
        final criticalBattery = BatteryState(
          level: 8,
          isCharging: false,
          isPowerSaveMode: false,
          isBackgrounded: false,
          lastUpdate: DateTime.now(),
        );

        expect(policy.shouldAttemptReconnection(criticalBattery, 1), true);
        expect(policy.shouldAttemptReconnection(criticalBattery, 2), true);
        expect(policy.shouldAttemptReconnection(criticalBattery, 3), false);
      });

      test('allows attempts when charging even with low battery', () {
        final chargingLowBattery = BatteryState(
          level: 5,
          isCharging: true,
          isPowerSaveMode: false,
          isBackgrounded: false,
          lastUpdate: DateTime.now(),
        );

        expect(policy.shouldAttemptReconnection(chargingLowBattery, 5), true);
      });

      test('gates background attempts after 5 failures', () {
        final backgroundState = BatteryState(
          level: 80,
          isCharging: false,
          isPowerSaveMode: false,
          isBackgrounded: true,
          lastUpdate: DateTime.now(),
        );

        expect(policy.shouldAttemptReconnection(backgroundState, 5), true);
        expect(policy.shouldAttemptReconnection(backgroundState, 6), false);
      });

      test('allows all attempts with good battery conditions', () {
        final goodBattery = BatteryState(
          level: 85,
          isCharging: false,
          isPowerSaveMode: false,
          isBackgrounded: false,
          lastUpdate: DateTime.now(),
        );

        for (int attempt = 0; attempt < 20; attempt++) {
          expect(policy.shouldAttemptReconnection(goodBattery, attempt), true,
              reason: 'Attempt $attempt should be allowed with good battery');
        }
      });
    });

    group('calculateReconnectionDelay', () {
      test('returns null when attempt is gated', () {
        final powerSaveState = BatteryState(
          level: 50,
          isCharging: false,
          isPowerSaveMode: true,
          isBackgrounded: false,
          lastUpdate: DateTime.now(),
        );

        final delay = policy.calculateReconnectionDelay(powerSaveState, 4);
        expect(delay, null);
      });

      test('returns Spec-compliant delay when attempt is allowed', () {
        final goodBattery = BatteryState(
          level: 80,
          isCharging: false,
          isPowerSaveMode: false,
          isBackgrounded: false,
          lastUpdate: DateTime.now(),
        );

        final delay = policy.calculateReconnectionDelay(goodBattery, 4);
        expect(delay, isNotNull);
        expect(delay!.inSeconds, inInclusiveRange(6, 10)); // 8s ±20% jitter
      });
    });

    group('getBatteryOptimizationMetrics', () {
      test('returns comprehensive battery metrics', () {
        final batteryState = BatteryState(
          level: 75,
          isCharging: true,
          isPowerSaveMode: false,
          isBackgrounded: false,
          lastUpdate: DateTime.now(),
        );

        final metrics = policy.getBatteryOptimizationMetrics(batteryState);

        expect(metrics['battery_level_percent'], 75);
        expect(metrics['battery_charging_status'], true);
        expect(metrics['power_save_mode_active'], false);
        expect(metrics['background_mode_active'], false);
        expect(metrics['should_optimize'], false);
        expect(metrics['is_critical'], false);
        expect(metrics['last_update'], isA<String>());
      });
    });
  });
}