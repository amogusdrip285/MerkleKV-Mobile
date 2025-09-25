/// Client-side cache configuration optimized for mobile constraints.
///
/// Provides configurable cache policies, memory limits, and battery-aware
/// behavior to balance performance with resource constraints on mobile devices.
class CacheConfig {
  /// Maximum memory usage in MB for the cache.
  /// Default: 50MB - balanced for mobile devices
  final int maxMemoryMB;

  /// Default TTL for cached entries.
  /// Default: 5 minutes - balances freshness with performance
  final Duration defaultTTL;

  /// Cache eviction and expiration policy.
  final CachePolicy policy;

  /// Whether to enable battery-aware refresh behavior.
  /// When enabled, reduces background operations when battery is low.
  final bool batteryAwareRefresh;

  /// Set of keys that should never be cached (e.g., sensitive data).
  final Set<String> excludedKeys;

  /// Whether to enable cache warming for frequently accessed keys.
  final bool enableCacheWarming;

  /// Threshold for cache warming - minimum access count to be considered frequent.
  final int warmingThreshold;

  /// Maximum number of entries to keep in the cache.
  /// Used as a fallback limit when memory-based limits aren't sufficient.
  final int maxEntries;

  /// Background cleanup interval for expired entries.
  final Duration cleanupInterval;

  /// Battery level threshold below which to reduce cache refresh operations.
  /// Default: 20% - typical low battery threshold
  final int lowBatteryThreshold;

  const CacheConfig({
    this.maxMemoryMB = 50,
    this.defaultTTL = const Duration(minutes: 5),
    this.policy = CachePolicy.hybrid,
    this.batteryAwareRefresh = true,
    this.excludedKeys = const <String>{},
    this.enableCacheWarming = true,
    this.warmingThreshold = 5,
    this.maxEntries = 10000,
    this.cleanupInterval = const Duration(minutes: 1),
    this.lowBatteryThreshold = 20,
  });

  /// Creates a copy with modified values.
  CacheConfig copyWith({
    int? maxMemoryMB,
    Duration? defaultTTL,
    CachePolicy? policy,
    bool? batteryAwareRefresh,
    Set<String>? excludedKeys,
    bool? enableCacheWarming,
    int? warmingThreshold,
    int? maxEntries,
    Duration? cleanupInterval,
    int? lowBatteryThreshold,
  }) {
    return CacheConfig(
      maxMemoryMB: maxMemoryMB ?? this.maxMemoryMB,
      defaultTTL: defaultTTL ?? this.defaultTTL,
      policy: policy ?? this.policy,
      batteryAwareRefresh: batteryAwareRefresh ?? this.batteryAwareRefresh,
      excludedKeys: excludedKeys ?? this.excludedKeys,
      enableCacheWarming: enableCacheWarming ?? this.enableCacheWarming,
      warmingThreshold: warmingThreshold ?? this.warmingThreshold,
      maxEntries: maxEntries ?? this.maxEntries,
      cleanupInterval: cleanupInterval ?? this.cleanupInterval,
      lowBatteryThreshold: lowBatteryThreshold ?? this.lowBatteryThreshold,
    );
  }

  @override
  String toString() {
    return 'CacheConfig('
        'maxMemoryMB: $maxMemoryMB, '
        'defaultTTL: $defaultTTL, '
        'policy: $policy, '
        'batteryAwareRefresh: $batteryAwareRefresh, '
        'excludedKeys: ${excludedKeys.length} keys, '
        'enableCacheWarming: $enableCacheWarming, '
        'maxEntries: $maxEntries'
        ')';
  }
}

/// Cache eviction and expiration policies.
enum CachePolicy {
  /// Least Recently Used - evicts entries based on access patterns.
  /// Best for memory-constrained environments.
  lru,

  /// Time To Live - evicts entries based on age.
  /// Best for ensuring data freshness.
  ttl,

  /// Hybrid LRU+TTL - combines both strategies.
  /// Recommended for mobile applications.
  hybrid,
}