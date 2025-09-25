import 'dart:async';
import 'package:merkle_kv_core/merkle_kv_core.dart';

/// Example demonstrating client-side caching with MerkleKV Mobile.
///
/// This example shows how to configure and use the intelligent caching
/// system for improved performance on mobile devices.
void main() async {
  print('🚀 MerkleKV Mobile - Client-side Caching Example');
  print('');

  // Step 1: Configure the MerkleKV client with caching enabled
  print('📝 Step 1: Creating configuration with caching enabled...');
  
  final cacheConfig = CacheConfig(
    maxMemoryMB: 25, // Limit cache to 25MB for this example
    defaultTTL: Duration(minutes: 10), // 10-minute default expiration
    policy: CachePolicy.hybrid, // Use hybrid LRU+TTL policy
    batteryAwareRefresh: true, // Enable battery-aware behavior
    enableCacheWarming: true, // Enable cache warming
    excludedKeys: {'password', 'token', 'secret'}, // Don't cache sensitive data
  );

  final config = MerkleKVConfig.create(
    mqttHost: 'localhost',
    clientId: 'mobile-client-demo',
    nodeId: 'mobile-node-1',
    cacheConfig: cacheConfig,
  );

  print('✅ Configuration created:');
  print('   Cache: ${cacheConfig.maxMemoryMB}MB max, ${cacheConfig.defaultTTL.inMinutes}min TTL');
  print('   Policy: ${cacheConfig.policy}');
  print('   Battery Aware: ${cacheConfig.batteryAwareRefresh}');
  print('');

  // Step 2: Create storage with caching layer
  print('📚 Step 2: Creating cached storage...');
  
  final underlyingStorage = InMemoryStorage(config);
  await underlyingStorage.initialize();
  
  final cachedStorage = CachedStorage(underlyingStorage, cacheConfig);
  await cachedStorage.initialize();
  
  print('✅ Cached storage initialized');
  print('');

  // Step 3: Demonstrate cache performance
  print('🔄 Step 3: Demonstrating cache performance...');
  
  // Create some test data
  final entries = <String, StorageEntry>{};
  for (int i = 0; i < 10; i++) {
    entries['user:$i'] = StorageEntry(
      key: 'user:$i',
      value: '{"name": "User $i", "active": true, "score": ${100 + i * 10}}',
      nodeId: 'mobile-node-1',
      seq: i + 1,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      isTombstone: false,
    );
  }

  // Add data to storage
  for (final entry in entries.values) {
    await cachedStorage.put(entry.key, entry);
  }

  print('✅ Added ${entries.length} entries to storage');
  
  // Demonstrate cache warming
  await cachedStorage.warmCacheWithEntries(entries);
  print('🔥 Cache warmed with ${entries.length} entries');
  print('');

  // Step 4: Show cache hits vs misses
  print('📊 Step 4: Cache performance demonstration...');
  
  final stopwatch = Stopwatch();
  
  // First access (should be cache hits due to warming)
  stopwatch.start();
  for (int i = 0; i < 10; i++) {
    final result = await cachedStorage.get('user:$i');
    if (result != null && i == 0) {
      print('   Sample entry: user:0 = ${result.value}');
    }
  }
  stopwatch.stop();
  final cachedTime = stopwatch.elapsedMicroseconds;
  
  // Clear cache and access again (cache misses)
  await cachedStorage.clearCache();
  
  stopwatch.reset();
  stopwatch.start();
  for (int i = 0; i < 10; i++) {
    await cachedStorage.get('user:$i');
  }
  stopwatch.stop();
  final uncachedTime = stopwatch.elapsedMicroseconds;

  print('⚡ Performance comparison:');
  print('   Cached reads: ${cachedTime}μs (${(cachedTime / 1000).toStringAsFixed(2)}ms)');
  print('   Uncached reads: ${uncachedTime}μs (${(uncachedTime / 1000).toStringAsFixed(2)}ms)');
  if (uncachedTime > cachedTime) {
    final speedup = (uncachedTime / cachedTime).toStringAsFixed(1);
    print('   🚀 Cache provided ${speedup}x speedup!');
  }
  print('');

  // Step 5: Show cache statistics
  print('📈 Step 5: Cache statistics...');
  
  final stats = cachedStorage.getCacheStats();
  final metrics = stats['metrics'] as Map<String, dynamic>;
  
  print('Cache Metrics:');
  print('   Hit Rate: ${(metrics['hit_rate'] * 100).toStringAsFixed(1)}%');
  print('   Total Hits: ${metrics['hit_count']}');
  print('   Total Misses: ${metrics['miss_count']}');
  print('   Total Puts: ${metrics['put_count']}');
  print('   Cache Warmings: ${metrics['warming_count']}');
  print('   Memory Usage: ${stats['memory_usage_mb']} MB');
  print('   Entry Count: ${stats['entry_count']}');
  print('');

  // Step 6: Demonstrate cache invalidation
  print('🔄 Step 6: Cache invalidation demonstration...');
  
  // Update an entry
  final updatedEntry = StorageEntry(
    key: 'user:0',
    value: '{"name": "User 0 Updated", "active": true, "score": 999}',
    nodeId: 'mobile-node-1',
    seq: 100,
    timestampMs: DateTime.now().millisecondsSinceEpoch,
    isTombstone: false,
  );
  
  await cachedStorage.put('user:0', updatedEntry);
  
  // Verify cache was invalidated and updated
  final result = await cachedStorage.get('user:0');
  print('✅ Updated entry retrieved: ${result?.value}');
  
  // Simulate replication event invalidation
  await cachedStorage.onReplicationEventApplied('user:1');
  print('✅ Simulated replication event - cache invalidated for user:1');
  print('');

  // Step 7: Demonstrate TTL expiration
  print('⏰ Step 7: TTL expiration demonstration...');
  
  // Add entry with short TTL
  final shortTtlEntry = StorageEntry(
    key: 'temp:data',
    value: '{"temporary": true, "expires": "soon"}',
    nodeId: 'mobile-node-1',
    seq: 200,
    timestampMs: DateTime.now().millisecondsSinceEpoch,
    isTombstone: false,
  );
  
  await cachedStorage.put('temp:data', shortTtlEntry);
  await cachedStorage.cache.put('temp:data', shortTtlEntry, ttl: Duration(milliseconds: 100));
  
  print('📝 Added temporary entry with 100ms TTL');
  
  // Wait for expiration
  await Future.delayed(Duration(milliseconds: 150));
  
  // Trigger cleanup
  final cleanedCount = await cachedStorage.cache.cleanup();
  print('🧹 Cleanup removed $cleanedCount expired entries');
  print('');

  // Step 8: Final statistics
  print('📊 Final cache statistics:');
  final finalStats = cachedStorage.getCacheStats();
  final finalMetrics = finalStats['metrics'] as Map<String, dynamic>;
  
  print('   Final Hit Rate: ${(finalMetrics['hit_rate'] * 100).toStringAsFixed(1)}%');
  print('   Total Operations: ${finalMetrics['operation_count']}');
  print('   Cleanup Operations: ${finalMetrics['cleanup_count']}');
  print('   Invalidations: ${finalMetrics['invalidation_count']}');
  print('   Peak Memory Usage: ${(finalMetrics['peak_memory_usage_bytes'] / 1024 / 1024).toStringAsFixed(2)} MB');
  print('');

  // Cleanup
  print('🧹 Cleaning up...');
  await cachedStorage.dispose();
  print('✅ Example completed successfully!');
  print('');
  print('💡 Key Benefits Demonstrated:');
  print('   • Automatic cache warming for faster startup');
  print('   • Cache-through pattern for consistent data');
  print('   • Intelligent invalidation on writes and replication');
  print('   • TTL-based expiration for data freshness');
  print('   • Comprehensive metrics for monitoring');
  print('   • Memory-efficient LRU eviction');
  print('   • Mobile-optimized defaults and battery awareness');
}