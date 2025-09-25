import 'dart:async';
import '../storage/storage_entry.dart';
import 'cache_metrics.dart';

/// Abstract interface for client-side caching with mobile optimizations.
///
/// Provides intelligent caching with configurable policies, memory management,
/// and battery-aware operations for mobile devices.
abstract class CacheInterface {
  /// Gets a cached entry if available and not expired.
  ///
  /// Returns null if the key is not cached, expired, or excluded from caching.
  /// Updates access tracking for LRU policy when entry is found.
  Future<StorageEntry?> get(String key);

  /// Puts an entry into the cache with TTL.
  ///
  /// Respects exclusion rules and memory limits. May evict other entries
  /// based on the configured cache policy.
  Future<void> put(String key, StorageEntry entry, {Duration? ttl});

  /// Removes an entry from the cache.
  ///
  /// Used for cache invalidation when data is updated or deleted.
  Future<void> invalidate(String key);

  /// Removes multiple entries from the cache.
  ///
  /// Efficient batch invalidation for operations affecting multiple keys.
  Future<void> invalidateKeys(Set<String> keys);

  /// Clears all cached entries.
  Future<void> clear();

  /// Gets cache performance metrics.
  CacheMetrics get metrics;

  /// Checks if a key is currently cached (not expired).
  bool contains(String key);

  /// Gets current memory usage in bytes.
  int get currentMemoryUsage;

  /// Gets current number of cached entries.
  int get entryCount;

  /// Performs background cleanup of expired entries.
  ///
  /// Should be called periodically to maintain cache health.
  /// Returns the number of entries removed.
  Future<int> cleanup();

  /// Warms the cache with frequently accessed keys.
  ///
  /// Loads specified keys into the cache if they're not already present.
  /// Useful for preloading data during app startup or network availability.
  Future<void> warmCache(Map<String, StorageEntry> entries);

  /// Gets keys that should be warmed based on access patterns.
  ///
  /// Returns keys that are frequently accessed but not currently cached.
  Set<String> getWarmingCandidates();

  /// Disposes of cache resources and stops background operations.
  Future<void> dispose();
}

/// Memory pressure levels for adaptive cache behavior.
enum MemoryPressure {
  /// Normal memory conditions.
  normal,
  
  /// Moderate memory pressure - reduce cache size.
  moderate,
  
  /// High memory pressure - aggressive eviction.
  high,
  
  /// Critical memory pressure - clear cache.
  critical,
}

/// Cache operation result information.
class CacheResult {
  /// Whether the operation was successful.
  final bool success;
  
  /// Whether the result came from cache (hit) or storage (miss).
  final bool isHit;
  
  /// Optional reason for failure or additional information.
  final String? reason;
  
  /// Time taken for the operation.
  final Duration duration;

  const CacheResult({
    required this.success,
    required this.isHit,
    this.reason,
    required this.duration,
  });

  /// Creates a successful cache hit result.
  factory CacheResult.hit(Duration duration) {
    return CacheResult(
      success: true,
      isHit: true,
      duration: duration,
    );
  }

  /// Creates a successful cache miss result.
  factory CacheResult.miss(Duration duration) {
    return CacheResult(
      success: true,
      isHit: false,
      duration: duration,
    );
  }

  /// Creates a failed operation result.
  factory CacheResult.failed(String reason, Duration duration) {
    return CacheResult(
      success: false,
      isHit: false,
      reason: reason,
      duration: duration,
    );
  }

  @override
  String toString() {
    return 'CacheResult('
        'success: $success, '
        'isHit: $isHit, '
        'duration: $duration'
        '${reason != null ? ', reason: $reason' : ''}'
        ')';
  }
}

/// Cache event types for observability.
enum CacheEventType {
  hit,
  miss,
  put,
  eviction,
  expiration,
  invalidation,
  cleanup,
  warming,
}

/// Cache event information for monitoring and debugging.
class CacheEvent {
  /// Type of cache event.
  final CacheEventType type;
  
  /// Key associated with the event.
  final String key;
  
  /// Timestamp when the event occurred.
  final DateTime timestamp;
  
  /// Additional metadata about the event.
  final Map<String, dynamic>? metadata;

  CacheEvent({
    required this.type,
    required this.key,
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'CacheEvent('
        'type: $type, '
        'key: $key, '
        'timestamp: $timestamp'
        '${metadata != null ? ', metadata: $metadata' : ''}'
        ')';
  }
}