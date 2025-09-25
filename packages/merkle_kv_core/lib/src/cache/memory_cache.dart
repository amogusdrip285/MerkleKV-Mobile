import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../storage/storage_entry.dart';
import '../utils/battery_awareness.dart';
import 'cache_config.dart';
import 'cache_entry.dart';
import 'cache_interface.dart';
import 'cache_metrics.dart';

/// Memory-efficient cache implementation with LRU, TTL, and mobile optimizations.
///
/// Features:
/// - LRU eviction policy with efficient O(1) operations
/// - TTL-based expiration with background cleanup
/// - Memory pressure detection and adaptive eviction
/// - Battery-aware background operations
/// - Cache warming for frequently accessed keys
/// - Comprehensive performance metrics
class MemoryCache implements CacheInterface {
  final CacheConfig _config;
  final CacheMetrics _metrics = CacheMetrics();
  final BatteryAwarenessManager? _batteryAwareness;

  /// Internal cache storage with LRU ordering.
  final LinkedHashMap<String, CacheEntry> _cache = LinkedHashMap<String, CacheEntry>();

  /// Background cleanup timer.
  Timer? _cleanupTimer;

  /// Whether the cache has been disposed.
  bool _disposed = false;

  /// Current memory usage in bytes.
  int _currentMemoryUsage = 0;

  /// Access frequency tracking for cache warming.
  final Map<String, int> _accessFrequency = <String, int>{};

  /// Stream controller for cache events.
  final StreamController<CacheEvent> _eventController = StreamController<CacheEvent>.broadcast();

  MemoryCache(
    this._config, {
    BatteryAwarenessManager? batteryAwareness,
  }) : _batteryAwareness = batteryAwareness {
    _startBackgroundCleanup();
  }

  @override
  CacheMetrics get metrics => _metrics;

  @override
  int get currentMemoryUsage => _currentMemoryUsage;

  @override
  int get entryCount => _cache.length;

  @override
  bool contains(String key) {
    if (_disposed) return false;
    
    final entry = _cache[key];
    return entry != null && !entry.isExpired;
  }

  @override
  Future<StorageEntry?> get(String key) async {
    if (_disposed) return null;
    
    final stopwatch = Stopwatch()..start();
    
    try {
      // Check if key is excluded from caching
      if (_config.excludedKeys.contains(key)) {
        _metrics.recordMiss();
        return null;
      }

      final cacheEntry = _cache[key];
      
      if (cacheEntry == null) {
        _metrics.recordMiss();
        _emitEvent(CacheEvent(type: CacheEventType.miss, key: key));
        return null;
      }

      // Check if entry has expired
      if (cacheEntry.isExpired) {
        _metrics.recordMiss();
        _metrics.recordExpiration();
        await _removeEntry(key);
        _emitEvent(CacheEvent(type: CacheEventType.expiration, key: key));
        return null;
      }

      // Update access tracking for LRU
      cacheEntry.markAccessed();
      _trackAccess(key);
      
      // Move to end for LRU ordering
      _cache.remove(key);
      _cache[key] = cacheEntry;

      _metrics.recordHit();
      _emitEvent(CacheEvent(type: CacheEventType.hit, key: key));
      
      return cacheEntry.entry;
    } finally {
      _metrics.recordOperationTime(stopwatch.elapsed);
    }
  }

  @override
  Future<void> put(String key, StorageEntry entry, {Duration? ttl}) async {
    if (_disposed) return;
    
    final stopwatch = Stopwatch()..start();
    
    try {
      // Check if key is excluded from caching
      if (_config.excludedKeys.contains(key)) {
        return;
      }

      final effectiveTTL = ttl ?? _config.defaultTTL;
      final cacheEntry = CacheEntry.fromStorageEntry(entry, effectiveTTL);

      // Remove existing entry if present
      if (_cache.containsKey(key)) {
        await _removeEntry(key);
      }

      // Check memory constraints before adding
      await _ensureMemoryConstraints(cacheEntry.estimatedSize);

      // Add new entry
      _cache[key] = cacheEntry;
      _currentMemoryUsage += cacheEntry.estimatedSize;
      _metrics.updateMemoryUsage(_currentMemoryUsage);

      _metrics.recordPut();
      _emitEvent(CacheEvent(
        type: CacheEventType.put,
        key: key,
        metadata: {'size': cacheEntry.estimatedSize, 'ttl': effectiveTTL.inSeconds},
      ));
    } finally {
      _metrics.recordOperationTime(stopwatch.elapsed);
    }
  }

  @override
  Future<void> invalidate(String key) async {
    if (_disposed) return;
    
    if (_cache.containsKey(key)) {
      await _removeEntry(key);
      _metrics.recordInvalidation();
      _emitEvent(CacheEvent(type: CacheEventType.invalidation, key: key));
    }
  }

  @override
  Future<void> invalidateKeys(Set<String> keys) async {
    if (_disposed) return;
    
    for (final key in keys) {
      if (_cache.containsKey(key)) {
        await _removeEntry(key);
        _metrics.recordInvalidation();
        _emitEvent(CacheEvent(type: CacheEventType.invalidation, key: key));
      }
    }
  }

  @override
  Future<void> clear() async {
    if (_disposed) return;
    
    _cache.clear();
    _currentMemoryUsage = 0;
    _accessFrequency.clear();
    _metrics.updateMemoryUsage(0);
    _metrics.recordClear();
  }

  @override
  Future<int> cleanup() async {
    if (_disposed) return 0;
    
    final stopwatch = Stopwatch()..start();
    int removedCount = 0;
    
    try {
      final keysToRemove = <String>[];
      
      for (final entry in _cache.entries) {
        if (entry.value.isExpired) {
          keysToRemove.add(entry.key);
        }
      }
      
      for (final key in keysToRemove) {
        await _removeEntry(key);
        _metrics.recordExpiration();
        removedCount++;
      }
      
      _metrics.recordCleanup();
      
      if (removedCount > 0) {
        _emitEvent(CacheEvent(
          type: CacheEventType.cleanup,
          key: '',
          metadata: {'removed_count': removedCount},
        ));
      }
      
      return removedCount;
    } finally {
      _metrics.recordOperationTime(stopwatch.elapsed);
    }
  }

  @override
  Future<void> warmCache(Map<String, StorageEntry> entries) async {
    if (_disposed) return;
    
    // Check battery status for warming decisions
    if (_config.batteryAwareRefresh && _batteryAwareness != null) {
      final batteryStatus = _batteryAwareness!.currentStatus;
      if (batteryStatus != null && 
          batteryStatus.level < _config.lowBatteryThreshold && 
          !batteryStatus.isCharging) {
        _metrics.recordBatteryThrottle();
        return; // Skip warming to preserve battery
      }
    }

    for (final entry in entries.entries) {
      final key = entry.key;
      final storageEntry = entry.value;
      
      // Only warm if not already cached and not excluded
      if (!_cache.containsKey(key) && !_config.excludedKeys.contains(key)) {
        final cacheEntry = CacheEntry.fromStorageEntry(
          storageEntry,
          _config.defaultTTL,
          isWarmLoaded: true,
        );
        
        await _ensureMemoryConstraints(cacheEntry.estimatedSize);
        
        _cache[key] = cacheEntry;
        _currentMemoryUsage += cacheEntry.estimatedSize;
        _metrics.updateMemoryUsage(_currentMemoryUsage);
        _metrics.recordWarming();
        
        _emitEvent(CacheEvent(
          type: CacheEventType.warming,
          key: key,
          metadata: {'size': cacheEntry.estimatedSize},
        ));
      }
    }
  }

  @override
  Set<String> getWarmingCandidates() {
    if (_disposed) return <String>{};
    
    final candidates = <String>{};
    
    for (final entry in _accessFrequency.entries) {
      final key = entry.key;
      final count = entry.value;
      
      // Consider for warming if frequently accessed but not currently cached
      if (count >= _config.warmingThreshold && 
          !_cache.containsKey(key) &&
          !_config.excludedKeys.contains(key)) {
        candidates.add(key);
      }
    }
    
    return candidates;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    
    _disposed = true;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    
    await clear();
    await _eventController.close();
  }

  /// Stream of cache events for monitoring.
  Stream<CacheEvent> get events => _eventController.stream;

  /// Starts background cleanup timer.
  void _startBackgroundCleanup() {
    _cleanupTimer = Timer.periodic(_config.cleanupInterval, (_) async {
      if (!_disposed) {
        await cleanup();
      }
    });
  }

  /// Ensures memory constraints by evicting entries if necessary.
  Future<void> _ensureMemoryConstraints(int additionalSize) async {
    final maxMemoryBytes = _config.maxMemoryMB * 1024 * 1024;
    final projectedUsage = _currentMemoryUsage + additionalSize;
    
    if (projectedUsage <= maxMemoryBytes && _cache.length < _config.maxEntries) {
      return; // No eviction needed
    }

    // Calculate how much memory to free
    final targetUsage = (maxMemoryBytes * 0.8).round(); // 80% of max
    int memoryToFree = math.max(0, projectedUsage - targetUsage);
    
    if (_cache.length >= _config.maxEntries) {
      memoryToFree = math.max(memoryToFree, additionalSize);
    }

    await _evictEntries(memoryToFree);
  }

  /// Evicts entries using LRU policy until target memory is freed.
  Future<void> _evictEntries(int targetMemoryToFree) async {
    int memoryFreed = 0;
    final keysToEvict = <String>[];
    
    // LRU eviction - iterate from oldest (front) to newest (back)
    for (final entry in _cache.entries) {
      if (memoryFreed >= targetMemoryToFree) break;
      
      keysToEvict.add(entry.key);
      memoryFreed += entry.value.estimatedSize;
    }

    for (final key in keysToEvict) {
      await _removeEntry(key);
      _metrics.recordEviction();
      _emitEvent(CacheEvent(type: CacheEventType.eviction, key: key));
    }
  }

  /// Removes a single cache entry and updates memory tracking.
  Future<void> _removeEntry(String key) async {
    final entry = _cache.remove(key);
    if (entry != null) {
      _currentMemoryUsage -= entry.estimatedSize;
      _metrics.updateMemoryUsage(_currentMemoryUsage);
    }
  }

  /// Tracks key access frequency for cache warming.
  void _trackAccess(String key) {
    _accessFrequency[key] = (_accessFrequency[key] ?? 0) + 1;
    
    // Prevent unbounded growth of access frequency map
    if (_accessFrequency.length > _config.maxEntries * 2) {
      _pruneAccessFrequency();
    }
  }

  /// Prunes access frequency map to prevent unbounded growth.
  void _pruneAccessFrequency() {
    // Keep only the most frequently accessed keys
    final entries = _accessFrequency.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    
    _accessFrequency.clear();
    for (int i = 0; i < math.min(entries.length, _config.maxEntries); i++) {
      _accessFrequency[entries[i].key] = entries[i].value;
    }
  }

  /// Emits a cache event for observability.
  void _emitEvent(CacheEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }
}