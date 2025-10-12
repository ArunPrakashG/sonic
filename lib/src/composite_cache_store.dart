import 'cache.dart';

/// A composite cache that prefers the memory store and writes to both memory
/// and file stores. File hits are promoted into memory.
class CompositeCacheStore implements CacheStore {
  CompositeCacheStore({required this.memory, required this.file});

  final CacheStore memory;
  final CacheStore file;

  @override
  String makeKey(String method, String url, Map<String, dynamic>? query,
          Map<String, dynamic>? headers) =>
      memory.makeKey(method, url, query, headers);

  @override
  T? get<T>(String key, Duration ttl) {
    final m = memory.get<T>(key, ttl);
    if (m != null) {
      return m;
    }
    final f = file.get<T>(key, ttl);
    if (f != null) {
      // promote
      memory.put<T>(key, f);
      return f;
    }
    return null;
  }

  @override
  CacheHit<T>? getIfWithin<T>(String key, Duration window) {
    final m = memory.getIfWithin<T>(key, window);
    if (m != null) {
      return m;
    }
    final f = file.getIfWithin<T>(key, window);
    if (f != null) {
      memory.put<T>(key, f.data,
          headers: f.headers,
          statusCode: f.statusCode,
          message: f.message,
          etag: f.etag,
          lastModified: f.lastModified,
          mustValidate: f.mustValidate);
      return f;
    }
    return null;
  }

  @override
  CacheHit<T>? getWithMeta<T>(String key, Duration ttl) {
    final m = memory.getWithMeta<T>(key, ttl);
    if (m != null) {
      return m;
    }
    final f = file.getWithMeta<T>(key, ttl);
    if (f != null) {
      memory.put<T>(key, f.data,
          headers: f.headers,
          statusCode: f.statusCode,
          message: f.message,
          etag: f.etag,
          lastModified: f.lastModified,
          mustValidate: f.mustValidate);
      return f;
    }
    return null;
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
    memory.put<T>(key, value,
        headers: headers,
        statusCode: statusCode,
        message: message,
        etag: etag,
        ttl: ttl,
        lastModified: lastModified,
        mustValidate: mustValidate);
    file.put<T>(key, value,
        headers: headers,
        statusCode: statusCode,
        message: message,
        etag: etag,
        ttl: ttl,
        lastModified: lastModified,
        mustValidate: mustValidate);
  }

  @override
  void updateMeta(String key,
      {Map<String, List<String>>? headers,
      int? statusCode,
      String? message,
      String? etag,
      Duration? ttl,
      String? lastModified,
      bool? mustValidate}) {
    memory.updateMeta(key,
        headers: headers,
        statusCode: statusCode,
        message: message,
        etag: etag,
        ttl: ttl,
        lastModified: lastModified,
        mustValidate: mustValidate);
    file.updateMeta(key,
        headers: headers,
        statusCode: statusCode,
        message: message,
        etag: etag,
        ttl: ttl,
        lastModified: lastModified,
        mustValidate: mustValidate);
  }

  @override
  void remove(String key) {
    memory.remove(key);
    file.remove(key);
  }

  @override
  void clear() {
    memory.clear();
    file.clear();
  }
}
