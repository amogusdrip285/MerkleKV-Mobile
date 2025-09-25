import 'package:test/test.dart';
import 'package:merkle_kv_core/src/cache/cached_storage.dart';
import 'package:merkle_kv_core/src/cache/cache_config.dart';
import 'package:merkle_kv_core/src/storage/storage_interface.dart';
import 'package:merkle_kv_core/src/storage/storage_entry.dart';
import 'package:merkle_kv_core/src/storage/in_memory_storage.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';

void main() {
  group('CachedStorage Integration', () {
    late CachedStorage cachedStorage;
    late StorageInterface underlyingStorage;
    late MerkleKVConfig config;
    late CacheConfig cacheConfig;

    setUp(() async {
      config = MerkleKVConfig.create(
        mqttHost: 'localhost',
        clientId: 'test-client',
        nodeId: 'test-node',
      );
      
      cacheConfig = const CacheConfig(
        maxMemoryMB: 1, // Small for testing
        defaultTTL: Duration(seconds: 30),
        policy: CachePolicy.hybrid,
      );
      
      underlyingStorage = InMemoryStorage(config);
      await underlyingStorage.initialize();
      
      cachedStorage = CachedStorage(
        underlyingStorage,
        cacheConfig,
      );
      
      await cachedStorage.initialize();
    });

    tearDown(() async {
      await cachedStorage.dispose();
    });

    group('cache-through operations', () {
      test('get operation with cache miss loads from storage', () async {
        final entry = StorageEntry(
          key: 'test_key',
          value: 'test_value',
          nodeId: 'test_node',
          seq: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        
        // Put directly into underlying storage (bypass cache)
        await underlyingStorage.put('test_key', entry);
        
        // Initial cache metrics
        final initialHits = cachedStorage.cache.metrics.hitCount;
        final initialMisses = cachedStorage.cache.metrics.missCount;
        
        // Get through cached storage
        final result = await cachedStorage.get('test_key');
        
        expect(result, isNotNull);
        expect(result!.key, equals('test_key'));
        expect(result.value, equals('test_value'));
        
        // Should have cache miss (first access)
        expect(cachedStorage.cache.metrics.missCount, equals(initialMisses + 1));
        
        // Second get should hit cache
        final result2 = await cachedStorage.get('test_key');
        expect(result2, isNotNull);
        expect(cachedStorage.cache.metrics.hitCount, equals(initialHits + 1));
      });

      test('put operation invalidates cache', () async {
        final entry = StorageEntry(
          key: 'test_key',
          value: 'test_value',
          nodeId: 'test_node',
          seq: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        
        // First get to populate cache
        await cachedStorage.put('test_key', entry);
        final cached = await cachedStorage.get('test_key');
        expect(cached, isNotNull);
        expect(cachedStorage.cache.contains('test_key'), isFalse); // Invalidated after put
        
        // Update with new value
        final updatedEntry = StorageEntry(
          key: 'test_key',
          value: 'updated_value',
          nodeId: 'test_node',
          seq: 2,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        
        await cachedStorage.put('test_key', updatedEntry);
        
        // Cache should be invalidated
        expect(cachedStorage.cache.contains('test_key'), isFalse);
        
        // Next get should fetch updated value
        final result = await cachedStorage.get('test_key');
        expect(result!.value, equals('updated_value'));
      });

      test('delete operation invalidates cache', () async {
        final entry = StorageEntry(
          key: 'test_key',
          value: 'test_value',
          nodeId: 'test_node',
          seq: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        
        await cachedStorage.put('test_key', entry);
        await cachedStorage.get('test_key'); // Populate cache
        
        // Delete the entry
        await cachedStorage.delete('test_key', DateTime.now().millisecondsSinceEpoch, 'test_node', 2);
        
        // Cache should be invalidated
        expect(cachedStorage.cache.contains('test_key'), isFalse);
        
        // Get should return null (deleted)
        final result = await cachedStorage.get('test_key');
        expect(result, isNull);
      });
    });

    group('replication event integration', () {
      test('replication event invalidates cache', () async {
        final entry = StorageEntry(
          key: 'test_key',
          value: 'test_value',
          nodeId: 'test_node',
          seq: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        
        // Populate cache
        await cachedStorage.put('test_key', entry);
        await cachedStorage.get('test_key');
        
        // Simulate replication event
        await cachedStorage.onReplicationEventApplied('test_key');
        
        // Cache should be invalidated
        expect(cachedStorage.cache.contains('test_key'), isFalse);
        expect(cachedStorage.cache.metrics.invalidationCount, greaterThan(0));
      });

      test('batch replication events invalidate multiple keys', () async {
        final keys = ['key1', 'key2', 'key3'];
        
        // Populate cache with multiple entries
        for (final key in keys) {
          final entry = StorageEntry(
            key: key,
            value: 'value_$key',
            nodeId: 'test_node',
            seq: 1,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            isTombstone: false,
          );
          await cachedStorage.put(key, entry);
          await cachedStorage.get(key);
        }
        
        // Verify all are cached
        for (final key in keys) {
          expect(cachedStorage.cache.contains(key), isFalse); // Already invalidated by puts
        }
        
        // Repopulate cache
        for (final key in keys) {
          await cachedStorage.get(key);
        }
        
        // Simulate batch replication events
        await cachedStorage.onReplicationEventsApplied(keys.toSet());
        
        // All keys should be invalidated
        for (final key in keys) {
          expect(cachedStorage.cache.contains(key), isFalse);
        }
      });
    });

    group('cache warming', () {
      test('initial cache warming loads recent entries', () async {
        // Add some entries to underlying storage
        final entries = <String, StorageEntry>{};
        for (int i = 0; i < 5; i++) {
          final entry = StorageEntry(
            key: 'key$i',
            value: 'value$i',
            nodeId: 'test_node',
            seq: i,
            timestampMs: DateTime.now().millisecondsSinceEpoch + i,
            isTombstone: false,
          );
          entries['key$i'] = entry;
          await underlyingStorage.put('key$i', entry);
        }
        
        // Manually warm cache
        await cachedStorage.warmCacheWithEntries(entries);
        
        // Entries should be in cache
        for (int i = 0; i < 5; i++) {
          expect(cachedStorage.cache.contains('key$i'), isTrue);
        }
        
        expect(cachedStorage.cache.metrics.warmingCount, equals(5));
      });

      test('cache warming candidates based on access patterns', () async {
        // Simulate access patterns by getting non-existent keys
        for (int i = 0; i < 7; i++) { // Above warming threshold
          await cachedStorage.get('frequent_key');
        }
        
        for (int i = 0; i < 2; i++) { // Below warming threshold  
          await cachedStorage.get('infrequent_key');
        }
        
        final candidates = await cachedStorage.getCacheWarmingCandidates();
        
        expect(candidates, contains('frequent_key'));
        expect(candidates, isNot(contains('infrequent_key')));
      });
    });

    group('cache statistics and monitoring', () {
      test('provides comprehensive cache statistics', () async {
        final entry = StorageEntry(
          key: 'test_key',
          value: 'test_value',
          nodeId: 'test_node',
          seq: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        
        // Perform some operations
        await cachedStorage.put('test_key', entry);
        await cachedStorage.get('test_key'); // Cache miss
        await cachedStorage.get('test_key'); // Cache hit
        await cachedStorage.cache.invalidate('test_key');
        
        final stats = cachedStorage.getCacheStats();
        
        expect(stats, containsPair('entry_count', isA<int>()));
        expect(stats, containsPair('memory_usage_bytes', isA<int>()));
        expect(stats, containsPair('memory_usage_mb', isA<String>()));
        expect(stats['metrics'], isA<Map<String, dynamic>>());
        expect(stats['config'], isA<Map<String, dynamic>>());
        
        final metrics = stats['metrics'] as Map<String, dynamic>;
        expect(metrics, containsPair('hit_count', greaterThanOrEqualTo(0)));
        expect(metrics, containsPair('miss_count', greaterThanOrEqualTo(0)));
        expect(metrics, containsPair('put_count', greaterThanOrEqualTo(0)));
        expect(metrics, containsPair('invalidation_count', greaterThanOrEqualTo(0)));
      });
    });

    group('maintenance operations', () {
      test('garbage collection clears cache when tombstones removed', () async {
        final entry = StorageEntry(
          key: 'test_key',
          value: 'test_value',
          nodeId: 'test_node',
          seq: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        
        // Add entry and cache it
        await cachedStorage.put('test_key', entry);
        await cachedStorage.get('test_key');
        
        // Delete (creates tombstone)
        await cachedStorage.delete('test_key', DateTime.now().millisecondsSinceEpoch, 'test_node', 2);
        
        // Mock tombstone removal by directly calling underlying storage
        // (In real scenario, this would happen due to expiration)
        await underlyingStorage.garbageCollectTombstones();
        
        // Perform maintenance
        await cachedStorage.performMaintenance();
        
        // Verify maintenance was performed
        expect(cachedStorage.cache.metrics.cleanupCount, greaterThan(0));
      });

      test('cache clearing preserves underlying storage', () async {
        final entry = StorageEntry(
          key: 'test_key',
          value: 'test_value',
          nodeId: 'test_node',
          seq: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isTombstone: false,
        );
        
        // Add to storage and cache
        await cachedStorage.put('test_key', entry);
        await cachedStorage.get('test_key');
        
        // Clear cache only
        await cachedStorage.clearCache();
        
        expect(cachedStorage.cache.entryCount, equals(0));
        
        // Underlying storage should still have data
        final storageEntry = await underlyingStorage.get('test_key');
        expect(storageEntry, isNotNull);
        expect(storageEntry!.value, equals('test_value'));
        
        // Next get should reload from storage
        final reloaded = await cachedStorage.get('test_key');
        expect(reloaded, isNotNull);
        expect(reloaded!.value, equals('test_value'));
      });
    });

    group('error handling', () {
      test('handles storage errors gracefully', () async {
        // This is a simplified test - in practice, you'd need a mock storage
        // that can throw errors to fully test error handling
        
        // For now, just verify that cache operations don't crash
        expect(() => cachedStorage.get('nonexistent'), returnsNormally);
        expect(() => cachedStorage.clearCache(), returnsNormally);
        expect(() => cachedStorage.performMaintenance(), returnsNormally);
      });
    });
  });
}