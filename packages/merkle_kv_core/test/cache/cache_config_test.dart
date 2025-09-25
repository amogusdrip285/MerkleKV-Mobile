import 'package:test/test.dart';
import 'package:merkle_kv_core/src/cache/cache_config.dart';

void main() {
  group('CacheConfig', () {
    test('has sensible defaults for mobile devices', () {
      const config = CacheConfig();
      
      expect(config.maxMemoryMB, equals(50));
      expect(config.defaultTTL, equals(Duration(minutes: 5)));
      expect(config.policy, equals(CachePolicy.hybrid));
      expect(config.batteryAwareRefresh, isTrue);
      expect(config.excludedKeys.isEmpty, isTrue);
      expect(config.enableCacheWarming, isTrue);
      expect(config.warmingThreshold, equals(5));
      expect(config.maxEntries, equals(10000));
      expect(config.cleanupInterval, equals(Duration(minutes: 1)));
      expect(config.lowBatteryThreshold, equals(20));
    });

    test('supports copyWith for configuration updates', () {
      const config = CacheConfig();
      
      final updated = config.copyWith(
        maxMemoryMB: 100,
        defaultTTL: Duration(minutes: 10),
        policy: CachePolicy.lru,
        batteryAwareRefresh: false,
        excludedKeys: {'secret_key'},
      );
      
      expect(updated.maxMemoryMB, equals(100));
      expect(updated.defaultTTL, equals(Duration(minutes: 10)));
      expect(updated.policy, equals(CachePolicy.lru));
      expect(updated.batteryAwareRefresh, isFalse);
      expect(updated.excludedKeys, equals({'secret_key'}));
      
      // Unchanged values should remain the same
      expect(updated.enableCacheWarming, equals(config.enableCacheWarming));
      expect(updated.warmingThreshold, equals(config.warmingThreshold));
    });

    test('has meaningful string representation', () {
      const config = CacheConfig(
        maxMemoryMB: 100,
        defaultTTL: Duration(minutes: 10),
        policy: CachePolicy.lru,
      );
      
      final str = config.toString();
      expect(str, contains('maxMemoryMB: 100'));
      expect(str, contains('defaultTTL: 0:10:00.000000'));
      expect(str, contains('policy: CachePolicy.lru'));
    });

    group('CachePolicy enum', () {
      test('has expected values', () {
        expect(CachePolicy.values, hasLength(3));
        expect(CachePolicy.values, contains(CachePolicy.lru));
        expect(CachePolicy.values, contains(CachePolicy.ttl));
        expect(CachePolicy.values, contains(CachePolicy.hybrid));
      });

      test('supports string conversion', () {
        expect(CachePolicy.lru.toString(), equals('CachePolicy.lru'));
        expect(CachePolicy.ttl.toString(), equals('CachePolicy.ttl'));
        expect(CachePolicy.hybrid.toString(), equals('CachePolicy.hybrid'));
      });
    });
  });
}