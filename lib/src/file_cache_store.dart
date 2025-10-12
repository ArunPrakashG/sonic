// ignore_for_file: avoid_slow_async_io
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'cache.dart';

/// A simple file-backed cache store. Not optimized for large-scale use, but
/// adequate as a persistent cache example.
class FileCacheStore implements CacheStore {
  FileCacheStore({required this.directoryPath, this.maxEntries = 512});

  final String directoryPath;
  final int maxEntries;

  Future<Directory> _dir() async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _hashKey(String key) {
    return base64Url.encode(utf8.encode(key));
  }

  @visibleForTesting
  String fileNameForKey(String key) => '${_hashKey(key)}.json';

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

  Future<_DiskEntry?> _read(String key) async {
    final dir = await _dir();
    final file = File('${dir.path}/${fileNameForKey(key)}');
    if (!await file.exists()) {
      return null;
    }
    final raw = await file.readAsString();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _DiskEntry.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  _DiskEntry? _readSync(String key) {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      return null;
    }
    final file = File('${dir.path}/${fileNameForKey(key)}');
    if (!file.existsSync()) {
      return null;
    }
    try {
      final raw = file.readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _DiskEntry.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, _DiskEntry entry) async {
    final dir = await _dir();
    final file = File('${dir.path}/${fileNameForKey(key)}');
    await file.writeAsString(jsonEncode(entry.toJson()));
    // Naive LRU trim: not implemented fully for brevity
  }

  @override
  T? get<T>(String key, Duration ttl) {
    final e = _readSync(key);
    if (e == null) {
      return null;
    }
    final now = DateTime.now();
    final isExpired = e.expiresAt != null
        ? now.isAfter(e.expiresAt!)
        : now.difference(e.insertedAt) > ttl;
    if (isExpired) {
      return null;
    }
    return e.data as T;
  }

  @override
  CacheHit<T>? getIfWithin<T>(String key, Duration window) {
    final e = _readSync(key);
    if (e == null) {
      return null;
    }
    final within = DateTime.now().difference(e.insertedAt) <= window;
    if (!within) {
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
      mustValidate: e.mustValidate,
    );
  }

  @override
  CacheHit<T>? getWithMeta<T>(String key, Duration ttl) {
    final e = _readSync(key);
    if (e == null) {
      return null;
    }
    final now = DateTime.now();
    final isExpired = e.expiresAt != null
        ? now.isAfter(e.expiresAt!)
        : now.difference(e.insertedAt) > ttl;
    if (isExpired) {
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
      mustValidate: e.mustValidate,
    );
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
    // Best-effort async write
    final expiresAt = ttl != null ? DateTime.now().add(ttl) : null;
    final entry = _DiskEntry(
      data: value,
      insertedAt: DateTime.now(),
      headers: headers,
      statusCode: statusCode,
      message: message,
      etag: etag,
      expiresAt: expiresAt,
      lastModified: lastModified,
      mustValidate: mustValidate,
    );
    // ignore: discarded_futures
    _write(key, entry);
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
    // Read-modify-write best-effort
    () async {
      final current = await _read(key);
      if (current == null) {
        return;
      }
      final now = DateTime.now();
      final newExpiresAt = ttl != null ? now.add(ttl) : current.expiresAt;
      final updated = current.copyWith(
        headers: headers ?? current.headers,
        statusCode: statusCode ?? current.statusCode,
        message: message ?? current.message,
        etag: etag ?? current.etag,
        insertedAt: now,
        expiresAt: newExpiresAt,
        lastModified: lastModified ?? current.lastModified,
        mustValidate: mustValidate ?? current.mustValidate,
      );
      await _write(key, updated);
    }();
  }

  @override
  Future<void> remove(String key) async {
    final dir = await _dir();
    final file = File('${dir.path}/${fileNameForKey(key)}');
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> clear() async {
    final dir = await _dir();
    final files = dir.listSync().whereType<File>();
    for (final f in files) {
      if (f.path.endsWith('.json')) {
        await f.delete();
      }
    }
  }
}

class _DiskEntry {
  _DiskEntry({
    required this.data,
    required this.insertedAt,
    required this.headers,
    required this.statusCode,
    required this.message,
    required this.etag,
    required this.expiresAt,
    this.lastModified,
    this.mustValidate,
  });

  final dynamic data;
  final DateTime insertedAt;
  final Map<String, List<String>>? headers;
  final int statusCode;
  final String? message;
  final String? etag;
  final DateTime? expiresAt;
  final String? lastModified;
  final bool? mustValidate;

  Map<String, dynamic> toJson() => {
        'data': data,
        'insertedAt': insertedAt.toIso8601String(),
        'headers': headers,
        'statusCode': statusCode,
        'message': message,
        'etag': etag,
        'expiresAt': expiresAt?.toIso8601String(),
        'lastModified': lastModified,
        'mustValidate': mustValidate,
      };

  // ignore: prefer_constructors_over_static_methods
  static _DiskEntry fromJson(Map<String, dynamic> json) => _DiskEntry(
        data: json['data'],
        insertedAt: DateTime.parse(json['insertedAt'] as String),
        headers: (json['headers'] as Map?)
            ?.map((k, v) => MapEntry(k as String, (v as List).cast<String>())),
        statusCode: json['statusCode'] as int,
        message: json['message'] as String?,
        etag: json['etag'] as String?,
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
        lastModified: json['lastModified'] as String?,
        mustValidate: json['mustValidate'] as bool?,
      );

  _DiskEntry copyWith({
    dynamic data,
    DateTime? insertedAt,
    Map<String, List<String>>? headers,
    int? statusCode,
    String? message,
    String? etag,
    DateTime? expiresAt,
    String? lastModified,
    bool? mustValidate,
  }) =>
      _DiskEntry(
        data: data ?? this.data,
        insertedAt: insertedAt ?? this.insertedAt,
        headers: headers ?? this.headers,
        statusCode: statusCode ?? this.statusCode,
        message: message ?? this.message,
        etag: etag ?? this.etag,
        expiresAt: expiresAt ?? this.expiresAt,
        lastModified: lastModified ?? this.lastModified,
        mustValidate: mustValidate ?? this.mustValidate,
      );
}
