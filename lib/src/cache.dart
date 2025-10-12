import 'package:meta/meta.dart';

@immutable
class CachePolicy {
  const CachePolicy({
    this.enabled = false,
    this.ttl = const Duration(minutes: 5),
    this.staleWhileRevalidate = const Duration(minutes: 10),
  });

  final bool enabled;
  final Duration ttl;
  final Duration staleWhileRevalidate;

  CachePolicy copyWith({
    bool? enabled,
    Duration? ttl,
    Duration? staleWhileRevalidate,
  }) {
    return CachePolicy(
      enabled: enabled ?? this.enabled,
      ttl: ttl ?? this.ttl,
      staleWhileRevalidate: staleWhileRevalidate ?? this.staleWhileRevalidate,
    );
  }
}

/// Abstract interface for a cache store implementation.
abstract class CacheStore {
  String makeKey(String method, String url, Map<String, dynamic>? query,
      Map<String, dynamic>? headers);

  T? get<T>(String key, Duration ttl);

  CacheHit<T>? getWithMeta<T>(String key, Duration ttl);

  CacheHit<T>? getIfWithin<T>(String key, Duration window);

  void put<T>(String key, T value,
      {Map<String, List<String>>? headers,
      int statusCode = 200,
      String? message,
      String? etag,
      Duration? ttl,
      String? lastModified,
      bool? mustValidate});

  void updateMeta(String key,
      {Map<String, List<String>>? headers,
      int? statusCode,
      String? message,
      String? etag,
      Duration? ttl,
      String? lastModified,
      bool? mustValidate});

  void remove(String key);

  void clear();
}

class _CacheEntry<T> {
  _CacheEntry({
    required this.data,
    required this.insertedAt,
    required this.headers,
    required this.statusCode,
    this.message,
    this.etag,
    this.expiresAt,
    this.lastModified,
    this.mustValidate,
  });
  final T data;
  final DateTime insertedAt;
  final Map<String, List<String>>? headers;
  final int statusCode;
  final String? message;
  final String? etag;
  final DateTime? expiresAt;
  final String? lastModified;
  final bool? mustValidate;
}

class CacheHit<T> {
  CacheHit(
      {required this.data,
      this.headers,
      required this.statusCode,
      this.message,
      required this.insertedAt,
      this.etag,
      this.lastModified,
      this.mustValidate});
  final T data;
  final Map<String, List<String>>? headers;
  final int statusCode;
  final String? message;
  final DateTime insertedAt;
  final String? etag;
  final String? lastModified;
  final bool? mustValidate;
}

/// A simple in-memory LRU cache with TTL support.
class InMemoryCacheStore implements CacheStore {
  InMemoryCacheStore({this.maxEntries = 256});

  final int maxEntries;

  final _map = <String, _CacheEntry<dynamic>>{};

  @override
  String makeKey(String method, String url, Map<String, dynamic>? query,
      Map<String, dynamic>? headers) {
    final q = (query ?? const {}).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final h = (headers ?? const {}).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final queryStr = q.map((e) => '${e.key}=${e.value}').join('&');
    final headerStr = h.map((e) => '${e.key}=${e.value}').join('&');
    return '$method|$url|$queryStr|$headerStr';
  }

  @override
  T? get<T>(String key, Duration ttl) {
    final e = _map.remove(key);
    if (e == null) {
      return null;
    }
    // Reinsert to update LRU order
    _map[key] = e;
    final now = DateTime.now();
    final isExpired = e.expiresAt != null
        ? now.isAfter(e.expiresAt!)
        : now.difference(e.insertedAt) > ttl;
    if (isExpired) {
      _map.remove(key);
      return null;
    }
    return e.data as T;
  }

  @override
  CacheHit<T>? getWithMeta<T>(String key, Duration ttl) {
    final e = _map[key];
    if (e == null) {
      return null;
    }
    final now = DateTime.now();
    final isExpired = e.expiresAt != null
        ? now.isAfter(e.expiresAt!)
        : now.difference(e.insertedAt) > ttl;
    if (isExpired) {
      // Keep the entry so SWR can use it later
      return null;
    }
    // Promote to MRU
    _map.remove(key);
    _map[key] = e;
    return CacheHit<T>(
        data: e.data as T,
        headers: e.headers,
        statusCode: e.statusCode,
        message: e.message,
        insertedAt: e.insertedAt,
        etag: e.etag,
        lastModified: e.lastModified,
        mustValidate: e.mustValidate);
  }

  /// Returns a cache entry if within a given window regardless of TTL.
  @override
  CacheHit<T>? getIfWithin<T>(String key, Duration window) {
    final e = _map.remove(key);
    if (e == null) {
      return null;
    }
    _map[key] = e;
    final within = DateTime.now().difference(e.insertedAt) <= window;
    if (!within) {
      _map.remove(key);
      return null;
    }
    return CacheHit<T>(
        data: e.data as T,
        headers: e.headers,
        statusCode: e.statusCode,
        message: e.message,
        insertedAt: e.insertedAt,
        etag: e.etag,
        lastModified: e.lastModified,
        mustValidate: e.mustValidate);
  }

  @override
  void put<T>(String key, T value,
      {Map<String, List<String>>? headers,
      int statusCode = 200,
      String? message,
      String? etag,
      Duration? ttl,
      String? lastModified,
      bool? mustValidate}) {
    final now = DateTime.now();
    final expiresAt = ttl != null ? now.add(ttl) : null;
    _map[key] = _CacheEntry<T>(
      data: value,
      insertedAt: now,
      headers: headers,
      statusCode: statusCode,
      message: message,
      etag: etag,
      expiresAt: expiresAt,
      lastModified: lastModified,
      mustValidate: mustValidate,
    );
    if (_map.length > maxEntries) {
      // Remove least recently used
      final firstKey = _map.keys.first;
      _map.remove(firstKey);
    }
  }

  /// Update only metadata and timestamp for an existing entry.
  @override
  void updateMeta(String key,
      {Map<String, List<String>>? headers,
      int? statusCode,
      String? message,
      String? etag,
      Duration? ttl,
      String? lastModified,
      bool? mustValidate}) {
    final existing = _map[key];
    if (existing == null) {
      return;
    }
    final now = DateTime.now();
    final newExpiresAt =
        ttl != null ? now.add(ttl) : existing.expiresAt; // preserve
    _map[key] = _CacheEntry<dynamic>(
      data: existing.data,
      insertedAt: now,
      headers: headers ?? existing.headers,
      statusCode: statusCode ?? existing.statusCode,
      message: message ?? existing.message,
      etag: etag ?? existing.etag,
      expiresAt: newExpiresAt,
      lastModified: lastModified ?? existing.lastModified,
      mustValidate: mustValidate ?? existing.mustValidate,
    );
  }

  @override
  void remove(String key) => _map.remove(key);

  @override
  void clear() => _map.clear();
}
