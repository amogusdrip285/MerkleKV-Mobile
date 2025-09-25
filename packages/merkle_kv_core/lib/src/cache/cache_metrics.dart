/// Performance metrics for cache operations and health monitoring.
class CacheMetrics {
  /// Total number of cache hits since initialization.
  int hitCount = 0;

  /// Total number of cache misses since initialization.
  int missCount = 0;

  /// Total number of entries put into the cache.
  int putCount = 0;

  /// Total number of entries evicted due to policy constraints.
  int evictionCount = 0;

  /// Total number of entries expired due to TTL.
  int expirationCount = 0;

  /// Total number of cache invalidations.
  int invalidationCount = 0;

  /// Total number of cache clearing operations.
  int clearCount = 0;

  /// Total number of cache warming operations.
  int warmingCount = 0;

  /// Total number of background cleanup operations performed.
  int cleanupCount = 0;

  /// Total memory allocated by cached entries in bytes.
  int totalMemoryUsage = 0;

  /// Peak memory usage since initialization.
  int peakMemoryUsage = 0;

  /// Number of times memory pressure triggered aggressive eviction.
  int memoryPressureEvents = 0;

  /// Number of times battery-aware behavior reduced cache operations.
  int batteryThrottleEvents = 0;

  /// Total time spent on cache operations (microseconds).
  int totalOperationTime = 0;

  /// Number of cache operations performed.
  int operationCount = 0;

  /// Start time for metrics collection.
  final DateTime startTime = DateTime.now();

  /// Cache hit rate as a percentage (0.0 to 1.0).
  double get hitRate {
    final total = hitCount + missCount;
    return total > 0 ? hitCount / total : 0.0;
  }

  /// Cache miss rate as a percentage (0.0 to 1.0).
  double get missRate => 1.0 - hitRate;

  /// Average operation time in microseconds.
  double get averageOperationTime {
    return operationCount > 0 ? totalOperationTime / operationCount : 0.0;
  }

  /// Time since metrics collection started.
  Duration get uptime => DateTime.now().difference(startTime);

  /// Records a cache hit event.
  void recordHit() {
    hitCount++;
  }

  /// Records a cache miss event.
  void recordMiss() {
    missCount++;
  }

  /// Records a cache put operation.
  void recordPut() {
    putCount++;
  }

  /// Records an eviction event.
  void recordEviction() {
    evictionCount++;
  }

  /// Records an expiration event.
  void recordExpiration() {
    expirationCount++;
  }

  /// Records a cache invalidation.
  void recordInvalidation() {
    invalidationCount++;
  }

  /// Records a cache clear operation.
  void recordClear() {
    clearCount++;
  }

  /// Records a cache warming operation.
  void recordWarming() {
    warmingCount++;
  }

  /// Records a cleanup operation.
  void recordCleanup() {
    cleanupCount++;
  }

  /// Records memory pressure event.
  void recordMemoryPressure() {
    memoryPressureEvents++;
  }

  /// Records battery throttling event.
  void recordBatteryThrottle() {
    batteryThrottleEvents++;
  }

  /// Updates memory usage statistics.
  void updateMemoryUsage(int newUsage) {
    totalMemoryUsage = newUsage;
    if (newUsage > peakMemoryUsage) {
      peakMemoryUsage = newUsage;
    }
  }

  /// Records operation timing.
  void recordOperationTime(Duration duration) {
    totalOperationTime += duration.inMicroseconds;
    operationCount++;
  }

  /// Resets all metrics to zero.
  void reset() {
    hitCount = 0;
    missCount = 0;
    putCount = 0;
    evictionCount = 0;
    expirationCount = 0;
    invalidationCount = 0;
    clearCount = 0;
    warmingCount = 0;
    cleanupCount = 0;
    totalMemoryUsage = 0;
    peakMemoryUsage = 0;
    memoryPressureEvents = 0;
    batteryThrottleEvents = 0;
    totalOperationTime = 0;
    operationCount = 0;
  }

  /// Creates a snapshot of current metrics as a map.
  Map<String, dynamic> toMap() {
    return {
      'hit_count': hitCount,
      'miss_count': missCount,
      'hit_rate': hitRate,
      'miss_rate': missRate,
      'put_count': putCount,
      'eviction_count': evictionCount,
      'expiration_count': expirationCount,
      'invalidation_count': invalidationCount,
      'clear_count': clearCount,
      'warming_count': warmingCount,
      'cleanup_count': cleanupCount,
      'memory_usage_bytes': totalMemoryUsage,
      'peak_memory_usage_bytes': peakMemoryUsage,
      'memory_pressure_events': memoryPressureEvents,
      'battery_throttle_events': batteryThrottleEvents,
      'average_operation_time_us': averageOperationTime,
      'operation_count': operationCount,
      'uptime_seconds': uptime.inSeconds,
    };
  }

  @override
  String toString() {
    return 'CacheMetrics('
        'hitRate: ${(hitRate * 100).toStringAsFixed(1)}%, '
        'hits: $hitCount, '
        'misses: $missCount, '
        'puts: $putCount, '
        'evictions: $evictionCount, '
        'memory: ${(totalMemoryUsage / 1024 / 1024).toStringAsFixed(1)}MB, '
        'operations: $operationCount, '
        'uptime: ${uptime.inMinutes}m'
        ')';
  }
}