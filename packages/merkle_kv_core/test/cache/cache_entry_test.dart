import 'package:test/test.dart';
import 'package:merkle_kv_core/src/cache/cache_entry.dart';
import 'package:merkle_kv_core/src/storage/storage_entry.dart';

void main() {
  group('CacheEntry', () {
    late StorageEntry testStorageEntry;
    
    setUp(() {
      testStorageEntry = StorageEntry(
        key: 'test_key',
        value: 'test_value',
        nodeId: 'test_node',
        seq: 1,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isTombstone: false,
      );
    });

    test('creates cache entry from storage entry with TTL', () {
      final ttl = Duration(minutes: 5);
      final cacheEntry = CacheEntry.fromStorageEntry(testStorageEntry, ttl);
      
      expect(cacheEntry.entry, equals(testStorageEntry));
      expect(cacheEntry.accessCount, equals(1));
      expect(cacheEntry.isWarmLoaded, isFalse);
      expect(cacheEntry.estimatedSize, greaterThan(0));
      
      // TTL should be approximately correct
      final timeDiff = cacheEntry.expiresAt.difference(DateTime.now());
      expect(timeDiff.inMinutes, closeTo(5, 1));
    });

    test('calculates estimated size correctly', () {
      final smallEntry = StorageEntry(
        key: 'k',
        value: 'v',
        nodeId: 'n',
        seq: 1,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isTombstone: false,
      );
      
      final largeEntry = StorageEntry(
        key: 'very_long_key_name',
        value: 'very_long_value_content' * 10,
        nodeId: 'node',
        seq: 1,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isTombstone: false,
      );
      
      final smallCache = CacheEntry.fromStorageEntry(smallEntry, Duration(minutes: 1));
      final largeCache = CacheEntry.fromStorageEntry(largeEntry, Duration(minutes: 1));
      
      expect(largeCache.estimatedSize, greaterThan(smallCache.estimatedSize));
    });

    test('handles tombstone entries correctly', () {
      final tombstone = StorageEntry(
        key: 'deleted_key',
        value: null,
        nodeId: 'test_node',
        seq: 1,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isTombstone: true,
      );
      
      final cacheEntry = CacheEntry.fromStorageEntry(tombstone, Duration(minutes: 1));
      
      expect(cacheEntry.entry.isTombstone, isTrue);
      expect(cacheEntry.entry.value, isNull);
      // Size should still be calculated for key and metadata
      expect(cacheEntry.estimatedSize, greaterThan(0));
    });

    test('tracks access correctly', () {
      final cacheEntry = CacheEntry.fromStorageEntry(testStorageEntry, Duration(minutes: 5));
      final initialLastAccess = cacheEntry.lastAccessTime;
      final initialCount = cacheEntry.accessCount;
      
      // Wait a small amount to ensure timestamp difference
      Future.delayed(Duration(milliseconds: 1), () {
        cacheEntry.markAccessed();
        
        expect(cacheEntry.accessCount, equals(initialCount + 1));
        expect(cacheEntry.lastAccessTime.isAfter(initialLastAccess), isTrue);
      });
    });

    test('correctly identifies expired entries', () {
      // Create expired entry
      final expiredEntry = CacheEntry(
        entry: testStorageEntry,
        expiresAt: DateTime.now().subtract(Duration(minutes: 1)),
      );
      
      // Create valid entry
      final validEntry = CacheEntry(
        entry: testStorageEntry,
        expiresAt: DateTime.now().add(Duration(minutes: 1)),
      );
      
      expect(expiredEntry.isExpired, isTrue);
      expect(validEntry.isExpired, isFalse);
    });

    test('calculates time since last access correctly', () {
      final cacheEntry = CacheEntry(
        entry: testStorageEntry,
        expiresAt: DateTime.now().add(Duration(minutes: 5)),
        lastAccessTime: DateTime.now().subtract(Duration(minutes: 2)),
      );
      
      final timeSinceAccess = cacheEntry.timeSinceLastAccess;
      expect(timeSinceAccess.inMinutes, closeTo(2, 1));
    });

    test('calculates time until expiration correctly', () {
      final cacheEntry = CacheEntry(
        entry: testStorageEntry,
        expiresAt: DateTime.now().add(Duration(minutes: 3)),
      );
      
      final timeUntilExpiration = cacheEntry.timeUntilExpiration;
      expect(timeUntilExpiration.inMinutes, closeTo(3, 1));
    });

    test('identifies hot entries correctly', () {
      final hotEntry = CacheEntry(
        entry: testStorageEntry,
        expiresAt: DateTime.now().add(Duration(minutes: 5)),
        lastAccessTime: DateTime.now().subtract(Duration(minutes: 5)),
        accessCount: 10, // High access count
      );
      
      final coldEntry = CacheEntry(
        entry: testStorageEntry,
        expiresAt: DateTime.now().add(Duration(minutes: 5)),
        lastAccessTime: DateTime.now().subtract(Duration(minutes: 15)),
        accessCount: 2, // Low access count
      );
      
      expect(hotEntry.isHot, isFalse); // Too old even with high access count
      expect(coldEntry.isHot, isFalse);
    });

    test('supports warm loaded flag', () {
      final warmEntry = CacheEntry.fromStorageEntry(
        testStorageEntry,
        Duration(minutes: 5),
        isWarmLoaded: true,
      );
      
      expect(warmEntry.isWarmLoaded, isTrue);
    });

    test('has meaningful string representation', () {
      final cacheEntry = CacheEntry.fromStorageEntry(testStorageEntry, Duration(minutes: 5));
      final str = cacheEntry.toString();
      
      expect(str, contains('CacheEntry'));
      expect(str, contains('key: test_key'));
      expect(str, contains('accessCount: 1'));
      expect(str, contains('size:'));
      expect(str, contains('isExpired:'));
      expect(str, contains('isWarmLoaded: false'));
    });

    test('supports equality comparison', () {
      final entry1 = CacheEntry.fromStorageEntry(testStorageEntry, Duration(minutes: 5));
      final entry2 = CacheEntry.fromStorageEntry(testStorageEntry, Duration(minutes: 5));
      
      // Different instances with different expiration times should not be equal
      expect(entry1, isNot(equals(entry2)));
      
      // Same instance should be equal to itself
      expect(entry1, equals(entry1));
    });

    test('hash code is consistent', () {
      final entry = CacheEntry.fromStorageEntry(testStorageEntry, Duration(minutes: 5));
      final hash1 = entry.hashCode;
      final hash2 = entry.hashCode;
      
      expect(hash1, equals(hash2));
    });
  });
}