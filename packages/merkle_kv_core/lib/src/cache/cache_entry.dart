import '../storage/storage_entry.dart';

/// Cached entry with metadata for efficient memory management and TTL tracking.
class CacheEntry {
  /// The cached storage entry.
  final StorageEntry entry;

  /// Cache-specific expiration time (independent of storage entry TTL).
  final DateTime expiresAt;

  /// Last access timestamp for LRU tracking.
  DateTime lastAccessTime;

  /// Number of times this entry has been accessed.
  int accessCount;

  /// Estimated memory size in bytes for this cache entry.
  final int estimatedSize;

  /// Whether this entry was loaded via cache warming.
  final bool isWarmLoaded;

  CacheEntry({
    required this.entry,
    required this.expiresAt,
    DateTime? lastAccessTime,
    this.accessCount = 1,
    int? estimatedSize,
    this.isWarmLoaded = false,
  }) : 
    lastAccessTime = lastAccessTime ?? DateTime.now(),
    estimatedSize = estimatedSize ?? _calculateSize(entry);

  /// Creates a cache entry from a storage entry with TTL.
  factory CacheEntry.fromStorageEntry(
    StorageEntry entry,
    Duration ttl, {
    bool isWarmLoaded = false,
  }) {
    return CacheEntry(
      entry: entry,
      expiresAt: DateTime.now().add(ttl),
      isWarmLoaded: isWarmLoaded,
    );
  }

  /// Whether this cache entry has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Updates the last access time and increments access count.
  void markAccessed() {
    lastAccessTime = DateTime.now();
    accessCount++;
  }

  /// Time since last access.
  Duration get timeSinceLastAccess => DateTime.now().difference(lastAccessTime);

  /// Time until expiration.
  Duration get timeUntilExpiration => expiresAt.difference(DateTime.now());

  /// Whether this entry should be considered "hot" for cache warming.
  bool get isHot => accessCount >= 5 && timeSinceLastAccess.inMinutes < 10;

  /// Estimates memory size of a storage entry in bytes.
  static int _calculateSize(StorageEntry entry) {
    // Key size + Value size (if not tombstone) + metadata overhead
    int size = entry.key.length * 2; // UTF-16 encoding
    
    if (!entry.isTombstone && entry.value != null) {
      size += entry.value!.length * 2; // UTF-16 encoding
    }
    
    // Add metadata overhead: timestamps, nodeId, etc.
    size += 100; // Estimated overhead for metadata
    
    return size;
  }

  @override
  String toString() {
    return 'CacheEntry('
        'key: ${entry.key}, '
        'expiresAt: $expiresAt, '
        'accessCount: $accessCount, '
        'size: $estimatedSize bytes, '
        'isExpired: $isExpired, '
        'isWarmLoaded: $isWarmLoaded'
        ')';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CacheEntry &&
          runtimeType == other.runtimeType &&
          entry == other.entry &&
          expiresAt == other.expiresAt;

  @override
  int get hashCode => entry.hashCode ^ expiresAt.hashCode;
}