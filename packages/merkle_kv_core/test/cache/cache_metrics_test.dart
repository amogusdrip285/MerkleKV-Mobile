import 'package:test/test.dart';
import 'package:merkle_kv_core/src/cache/cache_metrics.dart';

void main() {
  group('CacheMetrics', () {
    late CacheMetrics metrics;
    
    setUp(() {
      metrics = CacheMetrics();
    });

    test('initializes with zero values', () {
      expect(metrics.hitCount, equals(0));
      expect(metrics.missCount, equals(0));
      expect(metrics.putCount, equals(0));
      expect(metrics.evictionCount, equals(0));
      expect(metrics.expirationCount, equals(0));
      expect(metrics.invalidationCount, equals(0));
      expect(metrics.clearCount, equals(0));
      expect(metrics.warmingCount, equals(0));
      expect(metrics.cleanupCount, equals(0));
      expect(metrics.totalMemoryUsage, equals(0));
      expect(metrics.peakMemoryUsage, equals(0));
      expect(metrics.memoryPressureEvents, equals(0));
      expect(metrics.batteryThrottleEvents, equals(0));
      expect(metrics.totalOperationTime, equals(0));
      expect(metrics.operationCount, equals(0));
    });

    test('calculates hit rate correctly', () {
      expect(metrics.hitRate, equals(0.0));
      
      metrics.recordHit();
      expect(metrics.hitRate, equals(1.0));
      
      metrics.recordMiss();
      expect(metrics.hitRate, equals(0.5));
      
      metrics.recordHit();
      metrics.recordHit();
      expect(metrics.hitRate, equals(0.75));
    });

    test('calculates miss rate correctly', () {
      expect(metrics.missRate, equals(1.0));
      
      metrics.recordHit();
      expect(metrics.missRate, equals(0.0));
      
      metrics.recordMiss();
      expect(metrics.missRate, equals(0.5));
    });

    test('calculates average operation time correctly', () {
      expect(metrics.averageOperationTime, equals(0.0));
      
      metrics.recordOperationTime(Duration(microseconds: 100));
      expect(metrics.averageOperationTime, equals(100.0));
      
      metrics.recordOperationTime(Duration(microseconds: 200));
      expect(metrics.averageOperationTime, equals(150.0));
      
      metrics.recordOperationTime(Duration(microseconds: 300));
      expect(metrics.averageOperationTime, equals(200.0));
    });

    test('tracks memory usage and peak correctly', () {
      metrics.updateMemoryUsage(1000);
      expect(metrics.totalMemoryUsage, equals(1000));
      expect(metrics.peakMemoryUsage, equals(1000));
      
      metrics.updateMemoryUsage(2000);
      expect(metrics.totalMemoryUsage, equals(2000));
      expect(metrics.peakMemoryUsage, equals(2000));
      
      metrics.updateMemoryUsage(1500);
      expect(metrics.totalMemoryUsage, equals(1500));
      expect(metrics.peakMemoryUsage, equals(2000)); // Peak remains
    });

    test('records all event types', () {
      metrics.recordHit();
      expect(metrics.hitCount, equals(1));
      
      metrics.recordMiss();
      expect(metrics.missCount, equals(1));
      
      metrics.recordPut();
      expect(metrics.putCount, equals(1));
      
      metrics.recordEviction();
      expect(metrics.evictionCount, equals(1));
      
      metrics.recordExpiration();
      expect(metrics.expirationCount, equals(1));
      
      metrics.recordInvalidation();
      expect(metrics.invalidationCount, equals(1));
      
      metrics.recordClear();
      expect(metrics.clearCount, equals(1));
      
      metrics.recordWarming();
      expect(metrics.warmingCount, equals(1));
      
      metrics.recordCleanup();
      expect(metrics.cleanupCount, equals(1));
      
      metrics.recordMemoryPressure();
      expect(metrics.memoryPressureEvents, equals(1));
      
      metrics.recordBatteryThrottle();
      expect(metrics.batteryThrottleEvents, equals(1));
    });

    test('tracks uptime correctly', () {
      final startTime = DateTime.now();
      final uptime = metrics.uptime;
      
      expect(uptime.inSeconds, greaterThanOrEqualTo(0));
      expect(uptime.inSeconds, lessThan(1)); // Should be very recent
    });

    test('resets all metrics', () {
      // Set some values
      metrics.recordHit();
      metrics.recordMiss();
      metrics.recordPut();
      metrics.updateMemoryUsage(1000);
      metrics.recordOperationTime(Duration(microseconds: 100));
      
      expect(metrics.hitCount, equals(1));
      expect(metrics.totalMemoryUsage, equals(1000));
      
      // Reset
      metrics.reset();
      
      // All values should be zero
      expect(metrics.hitCount, equals(0));
      expect(metrics.missCount, equals(0));
      expect(metrics.putCount, equals(0));
      expect(metrics.evictionCount, equals(0));
      expect(metrics.expirationCount, equals(0));
      expect(metrics.invalidationCount, equals(0));
      expect(metrics.clearCount, equals(0));
      expect(metrics.warmingCount, equals(0));
      expect(metrics.cleanupCount, equals(0));
      expect(metrics.totalMemoryUsage, equals(0));
      expect(metrics.peakMemoryUsage, equals(0));
      expect(metrics.memoryPressureEvents, equals(0));
      expect(metrics.batteryThrottleEvents, equals(0));
      expect(metrics.totalOperationTime, equals(0));
      expect(metrics.operationCount, equals(0));
    });

    test('exports metrics as map', () {
      // Set some values
      metrics.recordHit();
      metrics.recordHit();
      metrics.recordMiss();
      metrics.recordPut();
      metrics.updateMemoryUsage(1500);
      metrics.recordOperationTime(Duration(microseconds: 200));
      
      final map = metrics.toMap();
      
      expect(map['hit_count'], equals(2));
      expect(map['miss_count'], equals(1));
      expect(map['hit_rate'], closeTo(0.67, 0.1));
      expect(map['miss_rate'], closeTo(0.33, 0.1));
      expect(map['put_count'], equals(1));
      expect(map['memory_usage_bytes'], equals(1500));
      expect(map['peak_memory_usage_bytes'], equals(1500));
      expect(map['average_operation_time_us'], equals(200.0));
      expect(map['operation_count'], equals(1));
      expect(map['uptime_seconds'], greaterThanOrEqualTo(0));
      
      // All keys should be present
      expect(map.keys, containsAll([
        'hit_count', 'miss_count', 'hit_rate', 'miss_rate',
        'put_count', 'eviction_count', 'expiration_count',
        'invalidation_count', 'clear_count', 'warming_count',
        'cleanup_count', 'memory_usage_bytes', 'peak_memory_usage_bytes',
        'memory_pressure_events', 'battery_throttle_events',
        'average_operation_time_us', 'operation_count', 'uptime_seconds'
      ]));
    });

    test('has meaningful string representation', () {
      metrics.recordHit();
      metrics.recordHit();
      metrics.recordMiss();
      metrics.recordPut();
      metrics.updateMemoryUsage(1024 * 1024); // 1MB
      
      final str = metrics.toString();
      
      expect(str, contains('CacheMetrics'));
      expect(str, contains('hitRate: 66.7%'));
      expect(str, contains('hits: 2'));
      expect(str, contains('misses: 1'));
      expect(str, contains('puts: 1'));
      expect(str, contains('memory: 1.0MB'));
      expect(str, contains('operations: 0'));
    });

    test('handles division by zero gracefully', () {
      // No hits or misses
      expect(metrics.hitRate, equals(0.0));
      expect(metrics.missRate, equals(1.0));
      
      // No operations
      expect(metrics.averageOperationTime, equals(0.0));
    });

    test('accumulates operation times correctly', () {
      metrics.recordOperationTime(Duration(microseconds: 100));
      metrics.recordOperationTime(Duration(microseconds: 200));
      metrics.recordOperationTime(Duration(microseconds: 300));
      
      expect(metrics.totalOperationTime, equals(600));
      expect(metrics.operationCount, equals(3));
      expect(metrics.averageOperationTime, equals(200.0));
    });
  });
}