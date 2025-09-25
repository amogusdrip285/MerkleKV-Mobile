import 'dart:async';
import 'package:test/test.dart';
import 'package:merkle_kv_core/src/cache/cache_config.dart';
import 'package:merkle_kv_core/src/cache/cache_interface.dart';
import 'package:merkle_kv_core/src/cache/memory_cache.dart';
import 'package:merkle_kv_core/src/storage/storage_entry.dart';
import 'package:merkle_kv_core/src/utils/battery_awareness.dart';

/// Mock battery awareness manager for testing
class MockBatteryAwarenessManager implements BatteryAwarenessManager {
  BatteryStatus? _currentStatus;
  BatteryAwarenessConfig _config = const BatteryAwarenessConfig();
  final StreamController<BatteryStatus> _statusController = StreamController<BatteryStatus>.broadcast();
  bool _isMonitoring = false;

  @override
  Stream<BatteryStatus> get batteryStatusStream => _statusController.stream;

  @override
  BatteryStatus? get currentStatus => _currentStatus;

  @override
  BatteryAwarenessConfig get config => _config;

  void setCurrentStatus(BatteryStatus status) {
    _currentStatus = status;
    if (_isMonitoring && !_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  @override
  BatteryOptimization getOptimization() {
    return const BatteryOptimization(
      keepAliveSeconds: 60,
      syncIntervalSeconds: 30,
      throttleOperations: false,
      reduceBackground: false,
      maxConcurrentOperations: 10,
      deferNonCriticalRequests: false,
    );
  }

  @override
  Future<void> startMonitoring() async {
    _isMonitoring = true;
  }

  @override
  Future<void> stopMonitoring() async {
    _isMonitoring = false;
  }

  @override
  void updateConfig(BatteryAwarenessConfig newConfig) {
    _config = newConfig;
  }

  @override
  Future<void> dispose() async {
    _isMonitoring = false;
    await _statusController.close();
  }
}

/// Helper function to create test storage entries with different keys/values
StorageEntry createTestEntry({
  String key = 'test_key',
  String? value = 'test_value',
  String nodeId = 'test_node',
  int seq = 1,
  bool isTombstone = false,
}) {
  return StorageEntry(
    key: key,
    value: value,
    nodeId: nodeId,
    seq: seq,
    timestampMs: DateTime.now().millisecondsSinceEpoch,
    isTombstone: isTombstone,
  );
}

void main() {
  group('MemoryCache', () {
    late MemoryCache cache;
    late CacheConfig config;
    late MockBatteryAwarenessManager batteryManager;
    late StorageEntry testEntry;

    setUp(() {
      config = const CacheConfig(
        maxMemoryMB: 1, // Small for testing
        defaultTTL: Duration(seconds: 30),
        policy: CachePolicy.hybrid,
        cleanupInterval: Duration(milliseconds: 100), // Fast for testing
      );
      
      batteryManager = MockBatteryAwarenessManager();
      cache = MemoryCache(config, batteryAwareness: batteryManager);
      
      testEntry = StorageEntry(
        key: 'test_key',
        value: 'test_value',
        nodeId: 'test_node',
        seq: 1,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isTombstone: false,
      );
    });

    tearDown(() async {
      await cache.dispose();
      await batteryManager.dispose();
    });

    group('basic operations', () {
      test('put and get operations work correctly', () async {
        expect(await cache.get('nonexistent'), isNull);
        expect(cache.contains('nonexistent'), isFalse);
        
        await cache.put('test_key', testEntry);
        
        expect(cache.contains('test_key'), isTrue);
        final retrieved = await cache.get('test_key');
        expect(retrieved, isNotNull);
        expect(retrieved!.key, equals('test_key'));
        expect(retrieved.value, equals('test_value'));
        
        expect(cache.entryCount, equals(1));
        expect(cache.currentMemoryUsage, greaterThan(0));
      });

      test('cache hit increments metrics', () async {
        await cache.put('test_key', testEntry);
        
        expect(cache.metrics.hitCount, equals(0));
        expect(cache.metrics.putCount, equals(1));
        
        await cache.get('test_key');
        
        expect(cache.metrics.hitCount, equals(1));
        expect(cache.metrics.missCount, equals(0));
      });

      test('cache miss increments metrics', () async {
        await cache.get('nonexistent');
        
        expect(cache.metrics.hitCount, equals(0));
        expect(cache.metrics.missCount, equals(1));
      });

      test('invalidate removes entries', () async {
        await cache.put('test_key', testEntry);
        expect(cache.contains('test_key'), isTrue);
        
        await cache.invalidate('test_key');
        expect(cache.contains('test_key'), isFalse);
        expect(cache.metrics.invalidationCount, equals(1));
      });

      test('invalidateKeys removes multiple entries', () async {
        final entry1 = StorageEntry(
          key: 'key1',
          value: 'value1',
          nodeId: 'test_node',
          seq: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        final entry2 = StorageEntry(
          key: 'key2',
          value: 'value2',
          nodeId: 'test_node',
          seq: 2,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        final entry3 = StorageEntry(
          key: 'key3',
          value: 'value3',
          nodeId: 'test_node',
          seq: 3,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        
        await cache.put('key1', entry1);
        await cache.put('key2', entry2);
        await cache.put('key3', entry3);
        
        expect(cache.entryCount, equals(3));
        
        await cache.invalidateKeys({'key1', 'key3', 'nonexistent'});
        
        expect(cache.entryCount, equals(1));
        expect(cache.contains('key2'), isTrue);
        expect(cache.metrics.invalidationCount, equals(2));
      });

      test('clear removes all entries', () async {
        final entry1 = StorageEntry(
          key: 'key1',
          value: 'value1',
          nodeId: 'test_node',
          seq: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        final entry2 = StorageEntry(
          key: 'key2',
          value: 'value2',
          nodeId: 'test_node',
          seq: 2,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        
        await cache.put('key1', entry1);
        await cache.put('key2', entry2);
        
        expect(cache.entryCount, equals(2));
        
        await cache.clear();
        
        expect(cache.entryCount, equals(0));
        expect(cache.currentMemoryUsage, equals(0));
        expect(cache.metrics.clearCount, equals(1));
      });
    });

    group('TTL expiration', () {
      test('expired entries are treated as cache miss', () async {
        final shortTTL = const Duration(milliseconds: 10);
        await cache.put('test_key', testEntry, ttl: shortTTL);
        
        expect(cache.contains('test_key'), isTrue);
        
        // Wait for expiration
        await Future.delayed(const Duration(milliseconds: 20));
        
        expect(cache.contains('test_key'), isFalse);
        expect(await cache.get('test_key'), isNull);
        expect(cache.metrics.expirationCount, equals(1));
      });

      test('cleanup removes expired entries', () async {
        final shortTTL = const Duration(milliseconds: 10);
        await cache.put('key1', createTestEntry(key: 'key1'), ttl: shortTTL);
        await cache.put('key2', createTestEntry(key: 'key2')); // Long TTL
        
        expect(cache.entryCount, equals(2));
        
        // Wait for first entry to expire
        await Future.delayed(const Duration(milliseconds: 20));
        
        final removedCount = await cache.cleanup();
        
        expect(removedCount, equals(1));
        expect(cache.entryCount, equals(1));
        expect(cache.contains('key2'), isTrue);
        expect(cache.metrics.cleanupCount, equals(1));
        expect(cache.metrics.expirationCount, equals(1));
      });
    });

    group('memory management', () {
      test('evicts entries when memory limit is reached', () async {
        // Create entries that will exceed the 1MB limit
        final largeValue = 'x' * (200 * 1024); // 200KB each
        
        for (int i = 0; i < 8; i++) {
          final entry = createTestEntry(key: 'key$i', value: largeValue);
          await cache.put('key$i', entry);
        }
        
        // Should have evicted some entries due to memory limit
        expect(cache.entryCount, lessThan(8));
        expect(cache.metrics.evictionCount, greaterThan(0));
        
        // Memory usage should be within reasonable bounds
        final memoryUsageMB = cache.currentMemoryUsage / (1024 * 1024);
        expect(memoryUsageMB, lessThanOrEqualTo(1.5)); // Allow some overage
      });

      test('tracks memory usage correctly', () async {
        final initialMemory = cache.currentMemoryUsage;
        expect(initialMemory, equals(0));
        
        await cache.put('test_key', testEntry);
        
        final afterPutMemory = cache.currentMemoryUsage;
        expect(afterPutMemory, greaterThan(initialMemory));
        
        await cache.invalidate('test_key');
        
        final afterInvalidateMemory = cache.currentMemoryUsage;
        expect(afterInvalidateMemory, equals(initialMemory));
      });
    });

    group('LRU eviction', () {
      test('evicts least recently used entries first', () async {
        final smallConfig = config.copyWith(maxEntries: 3);
        await cache.dispose();
        cache = MemoryCache(smallConfig);
        
        // Add entries
        await cache.put('key1', createTestEntry(key: 'key1'));
        await cache.put('key2', createTestEntry(key: 'key2'));
        await cache.put('key3', createTestEntry(key: 'key3'));
        
        // Access key1 to make it more recently used
        await cache.get('key1');
        
        // Add another entry, should evict key2 (least recently used)
        await cache.put('key4', createTestEntry(key: 'key4'));
        
        expect(cache.contains('key1'), isTrue);
        expect(cache.contains('key2'), isFalse); // Should be evicted
        expect(cache.contains('key3'), isTrue);
        expect(cache.contains('key4'), isTrue);
      });
    });

    group('excluded keys', () {
      test('does not cache excluded keys', () async {
        final configWithExclusions = config.copyWith(
          excludedKeys: {'secret_key', 'sensitive_data'},
        );
        await cache.dispose();
        cache = MemoryCache(configWithExclusions);
        
        await cache.put('secret_key', createTestEntry(key: 'secret_key'));
        await cache.put('normal_key', createTestEntry(key: 'normal_key'));
        
        expect(cache.contains('secret_key'), isFalse);
        expect(cache.contains('normal_key'), isTrue);
        expect(await cache.get('secret_key'), isNull);
        expect(await cache.get('normal_key'), isNotNull);
      });

      test('returns null for excluded keys on get', () async {
        final configWithExclusions = config.copyWith(
          excludedKeys: {'excluded_key'},
        );
        await cache.dispose();
        cache = MemoryCache(configWithExclusions);
        
        final result = await cache.get('excluded_key');
        expect(result, isNull);
        expect(cache.metrics.missCount, equals(1));
      });
    });

    group('cache warming', () {
      test('warms cache with provided entries', () async {
        final warmEntries = <String, StorageEntry>{
          'warm1': createTestEntry(key: 'warm1'),
          'warm2': createTestEntry(key: 'warm2'),
        };
        
        await cache.warmCache(warmEntries);
        
        expect(cache.contains('warm1'), isTrue);
        expect(cache.contains('warm2'), isTrue);
        expect(cache.metrics.warmingCount, equals(2));
      });

      test('skips warming for already cached entries', () async {
        await cache.put('existing', createTestEntry(key: 'existing'));
        
        final warmEntries = <String, StorageEntry>{
          'existing': createTestEntry(key: 'existing', value: 'different'),
          'new': createTestEntry(key: 'new'),
        };
        
        await cache.warmCache(warmEntries);
        
        // Should only warm the new entry
        expect(cache.metrics.warmingCount, equals(1));
        
        // Existing entry should remain unchanged
        final existing = await cache.get('existing');
        expect(existing!.value, equals('test_value'));
      });

      test('respects battery awareness during warming', () async {
        batteryManager.setCurrentStatus(BatteryStatus(
          level: 15, // Below threshold
          isCharging: false,
          isPowerSaveMode: true,
          isLowPowerMode: true,
          timestamp: DateTime.now(),
        ));
        
        await cache.dispose();
        cache = MemoryCache(config, batteryAwareness: batteryManager);
        
        final warmEntries = <String, StorageEntry>{
          'warm1': createTestEntry(key: 'warm1'),
        };
        
        await cache.warmCache(warmEntries);
        
        // Should skip warming due to low battery
        expect(cache.contains('warm1'), isFalse);
        expect(cache.metrics.batteryThrottleEvents, equals(1));
      });

      test('identifies warming candidates based on access frequency', () async {
        // Simulate frequent access to certain keys
        for (int i = 0; i < 6; i++) {
          await cache.get('frequent_key'); // Miss but tracked
        }
        
        for (int i = 0; i < 3; i++) {
          await cache.get('infrequent_key'); // Miss but tracked
        }
        
        final candidates = cache.getWarmingCandidates();
        
        expect(candidates, contains('frequent_key'));
        expect(candidates, isNot(contains('infrequent_key')));
      });
    });

    group('battery awareness', () {
      test('skips warming when battery is low and not charging', () async {
        batteryManager.setCurrentStatus(BatteryStatus(
          level: 10, // Very low
          isCharging: false,
          isPowerSaveMode: false,
          isLowPowerMode: false,
          timestamp: DateTime.now(),
        ));
        
        await cache.dispose();
        cache = MemoryCache(config, batteryAwareness: batteryManager);
        
        final warmEntries = <String, StorageEntry>{
          'test': testEntry,
        };
        
        await cache.warmCache(warmEntries);
        
        expect(cache.contains('test'), isFalse);
        expect(cache.metrics.batteryThrottleEvents, equals(1));
      });

      test('allows warming when battery is low but charging', () async {
        batteryManager.setCurrentStatus(BatteryStatus(
          level: 10, // Very low
          isCharging: true, // But charging
          isPowerSaveMode: false,
          isLowPowerMode: false,
          timestamp: DateTime.now(),
        ));
        
        await cache.dispose();
        cache = MemoryCache(config, batteryAwareness: batteryManager);
        
        final warmEntries = <String, StorageEntry>{
          'test': testEntry,
        };
        
        await cache.warmCache(warmEntries);
        
        expect(cache.contains('test'), isTrue);
        expect(cache.metrics.batteryThrottleEvents, equals(0));
      });
    });

    group('cache events', () {
      test('emits events for cache operations', () async {
        final events = <CacheEvent>[];
        final subscription = (cache as MemoryCache).events.listen(events.add);
        
        await cache.put('test', testEntry);
        await cache.get('test');
        await cache.get('missing');
        await cache.invalidate('test');
        
        await Future.delayed(Duration.zero); // Let events propagate
        
        expect(events, hasLength(4));
        expect(events.map((e) => e.type), containsAll([
          CacheEventType.put,
          CacheEventType.hit,
          CacheEventType.miss,
          CacheEventType.invalidation,
        ]));
        
        await subscription.cancel();
      });
    });

    group('disposal', () {
      test('disposes cleanly and stops operations', () async {
        await cache.put('test', testEntry);
        expect(cache.entryCount, equals(1));
        
        await cache.dispose();
        
        // Operations after disposal should be no-ops
        expect(await cache.get('test'), isNull);
        expect(cache.contains('test'), isFalse);
        
        await cache.put('new', testEntry); // Should be ignored
        expect(cache.entryCount, equals(0));
      });

      test('can be disposed multiple times safely', () async {
        await cache.dispose();
        await cache.dispose(); // Should not throw
      });
    });

    group('edge cases', () {
      test('handles null battery manager gracefully', () async {
        await cache.dispose();
        cache = MemoryCache(config, batteryAwareness: null);
        
        final warmEntries = <String, StorageEntry>{'test': testEntry};
        await cache.warmCache(warmEntries); // Should not throw
        
        expect(cache.contains('test'), isTrue);
      });

      test('handles tombstone entries correctly', () async {
        final tombstone = createTestEntry(
          key: 'tombstone',
          value: null,
          isTombstone: true,
        );
        
        await cache.put('tombstone', tombstone);
        
        final retrieved = await cache.get('tombstone');
        expect(retrieved, isNotNull);
        expect(retrieved!.isTombstone, isTrue);
        expect(retrieved.value, isNull);
      });

      test('handles very large number of access frequency entries', () async {
        // Create many access frequency entries to trigger pruning
        for (int i = 0; i < 25000; i++) {
          await cache.get('key_$i'); // All misses but tracked
        }
        
        final candidates = cache.getWarmingCandidates();
        // Should not crash and should have reasonable number of candidates
        expect(candidates.length, lessThanOrEqualTo(10000));
      });
    });
  });
}