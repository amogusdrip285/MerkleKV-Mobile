import 'dart:async';

import '../storage/storage_interface.dart';
import '../storage/storage_entry.dart';
import '../utils/battery_awareness.dart';
import 'cache_config.dart';
import 'cache_interface.dart';
import 'memory_cache.dart';

/// Storage implementation that adds intelligent caching to any storage backend.
///
/// Provides transparent caching with cache-through pattern, where reads check
/// the cache first and writes update both cache and underlying storage.
/// Implements cache invalidation on both local writes and replication events.
class CachedStorage implements StorageInterface {
  final StorageInterface _underlyingStorage;
  final CacheInterface _cache;
  final CacheConfig _config;

  /// Stream subscription for replication events (when available).
  StreamSubscription? _replicationSubscription;

  CachedStorage(
    this._underlyingStorage,
    this._config, {
    BatteryAwarenessManager? batteryAwarenessManager,
  }) : _cache = MemoryCache(_config, batteryAwareness: batteryAwarenessManager);

  /// Creates a cached storage with custom cache implementation.
  CachedStorage.withCache(
    this._underlyingStorage,
    this._cache,
    this._config,
  );

  /// Access to cache metrics and management.
  CacheInterface get cache => _cache;

  @override
  Future<void> initialize() async {
    await _underlyingStorage.initialize();
    
    // Pre-warm cache with frequently accessed data if enabled
    if (_config.enableCacheWarming) {
      await _performInitialCacheWarming();
    }
  }

  @override
  Future<StorageEntry?> get(String key) async {
    // Try cache first
    final cachedEntry = await _cache.get(key);
    if (cachedEntry != null) {
      return cachedEntry;
    }

    // Cache miss - get from underlying storage
    final storageEntry = await _underlyingStorage.get(key);
    
    // Cache the result if found
    if (storageEntry != null) {
      await _cache.put(key, storageEntry);
    }

    return storageEntry;
  }

  @override
  Future<void> put(String key, StorageEntry entry) async {
    // Update underlying storage first
    await _underlyingStorage.put(key, entry);
    
    // Invalidate cache to ensure consistency
    // The cache will be populated on next read
    await _cache.invalidate(key);
  }

  @override
  Future<void> putWithReconciliation(String key, StorageEntry entry) async {
    // Update underlying storage first
    await _underlyingStorage.putWithReconciliation(key, entry);
    
    // Invalidate cache since this is a reconciliation from replication
    await _cache.invalidate(key);
  }

  @override
  Future<void> delete(String key, int timestampMs, String nodeId, int seq) async {
    // Delete from underlying storage first
    await _underlyingStorage.delete(key, timestampMs, nodeId, seq);
    
    // Invalidate cache entry
    await _cache.invalidate(key);
  }

  @override
  Future<List<StorageEntry>> getAllEntries() async {
    // This operation bypasses cache and goes directly to storage
    // as it's typically used for replication and needs complete state
    return _underlyingStorage.getAllEntries();
  }

  @override
  Future<int> garbageCollectTombstones() async {
    // Perform garbage collection on underlying storage
    final removedCount = await _underlyingStorage.garbageCollectTombstones();
    
    // If tombstones were removed, we need to be cautious about cache validity
    // For simplicity, clear the cache to ensure consistency
    if (removedCount > 0) {
      await _cache.clear();
    }
    
    return removedCount;
  }

  @override
  Future<void> dispose() async {
    // Clean up replication subscription
    await _replicationSubscription?.cancel();
    _replicationSubscription = null;
    
    // Dispose cache
    await _cache.dispose();
    
    // Dispose underlying storage
    await _underlyingStorage.dispose();
  }

  /// Invalidates cache entries based on replication events.
  ///
  /// Should be called when replication events are applied to ensure
  /// cache consistency across distributed storage.
  Future<void> onReplicationEventApplied(String key) async {
    await _cache.invalidate(key);
  }

  /// Invalidates multiple cache entries based on replication events.
  ///
  /// Efficient batch invalidation for multiple replication events.
  Future<void> onReplicationEventsApplied(Set<String> keys) async {
    await _cache.invalidateKeys(keys);
  }

  /// Sets up replication event monitoring for automatic cache invalidation.
  ///
  /// When replication events are applied, affected cache entries will be
  /// automatically invalidated to maintain consistency.
  void setupReplicationEventMonitoring(Stream<String> replicationEvents) {
    _replicationSubscription?.cancel();
    _replicationSubscription = replicationEvents.listen((key) async {
      await _cache.invalidate(key);
    });
  }

  /// Performs background cache maintenance.
  ///
  /// Should be called periodically to clean up expired entries and
  /// optimize cache performance.
  Future<void> performMaintenance() async {
    await _cache.cleanup();
  }

  /// Pre-warms the cache with recently modified or frequently accessed data.
  ///
  /// This is called during initialization to improve initial performance
  /// by loading likely-to-be-accessed data into the cache.
  Future<void> _performInitialCacheWarming() async {
    try {
      // Get all entries from storage (this might be expensive, so consider limiting)
      final allEntries = await _underlyingStorage.getAllEntries();
      
      // Filter to non-tombstone entries and sort by timestamp (most recent first)
      final validEntries = allEntries
          .where((entry) => !entry.isTombstone)
          .toList();
      
      validEntries.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
      
      // Warm cache with most recent entries (limit to avoid memory issues)
      const int maxWarmEntries = 100;
      final entriesToWarm = validEntries.take(maxWarmEntries).toList();
      
      final warmingMap = <String, StorageEntry>{};
      for (final entry in entriesToWarm) {
        warmingMap[entry.key] = entry;
      }
      
      await _cache.warmCache(warmingMap);
    } catch (e) {
      // Ignore cache warming failures - they shouldn't prevent initialization
      // In production, this would be logged
    }
  }

  /// Gets cache warming candidates based on access patterns.
  ///
  /// Returns keys that should be preloaded into cache based on
  /// historical access patterns.
  Future<Set<String>> getCacheWarmingCandidates() async {
    return _cache.getWarmingCandidates();
  }

  /// Manually warms the cache with specific entries.
  ///
  /// Useful for preloading cache with data that is known to be
  /// frequently accessed.
  Future<void> warmCacheWithEntries(Map<String, StorageEntry> entries) async {
    await _cache.warmCache(entries);
  }

  /// Clears all cached data while preserving underlying storage.
  ///
  /// Useful for testing or when cache corruption is suspected.
  Future<void> clearCache() async {
    await _cache.clear();
  }

  /// Gets current cache statistics for monitoring and debugging.
  Map<String, dynamic> getCacheStats() {
    return {
      'metrics': _cache.metrics.toMap(),
      'entry_count': _cache.entryCount,
      'memory_usage_bytes': _cache.currentMemoryUsage,
      'memory_usage_mb': (_cache.currentMemoryUsage / 1024 / 1024).toStringAsFixed(2),
      'config': {
        'max_memory_mb': _config.maxMemoryMB,
        'default_ttl_seconds': _config.defaultTTL.inSeconds,
        'policy': _config.policy.toString(),
        'battery_aware': _config.batteryAwareRefresh,
        'cache_warming_enabled': _config.enableCacheWarming,
        'max_entries': _config.maxEntries,
      },
    };
  }
}