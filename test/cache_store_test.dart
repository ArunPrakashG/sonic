// ignore_for_file: avoid_slow_async_io
import 'dart:io';

import 'package:sonic/src/cache.dart';
import 'package:sonic/src/composite_cache_store.dart';
import 'package:sonic/src/file_cache_store.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryCacheStore', () {
    test('put/get within ttl', () {
      final store = InMemoryCacheStore();
      final key = store.makeKey('GET', '/a', {'q': 1}, {'h': 'v'});
      store.put(key, {'hello': 'world'}, ttl: const Duration(seconds: 5));
      final v =
          store.get<Map<String, dynamic>>(key, const Duration(seconds: 5));
      expect(v, isNotNull);
      expect(v!['hello'], 'world');
    });

    test('expired entry returns via getIfWithin', () async {
      final store = InMemoryCacheStore();
      final key = store.makeKey('GET', '/a', null, null);
      store.put(key, 42, ttl: const Duration(milliseconds: 5));
      // wait beyond ttl but within window
      await Future<void>.delayed(const Duration(milliseconds: 15));
      // don't call get(); getWithMeta returns null for expired
      final freshMeta =
          store.getWithMeta<int>(key, const Duration(milliseconds: 5));
      expect(freshMeta, isNull);
      final stale = store.getIfWithin<int>(key, const Duration(seconds: 5));
      expect(stale, isNotNull);
      expect(stale!.data, 42);
    });

    test('getWithMeta provides etag and lastModified when stored', () {
      final store = InMemoryCacheStore();
      final key = store.makeKey('GET', '/a', null, null);
      store.put(key, 1,
          etag: 'E1',
          lastModified: 'Sat, 11 Oct 2025 12:00:00 GMT',
          ttl: const Duration(seconds: 5),
          mustValidate: true);
      final hit = store.getWithMeta<int>(key, const Duration(seconds: 5));
      expect(hit, isNotNull);
      expect(hit!.etag, 'E1');
      expect(hit.lastModified, isNotEmpty);
      expect(hit.mustValidate, isTrue);
    });
  });

  group('FileCacheStore', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sonic_test_');
    });
    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    test('persists and loads entries with metadata', () async {
      final store = FileCacheStore(directoryPath: tmp.path);
      final key = store.makeKey('GET', '/b', null, null);
      store.put(key, {'k': 'v'},
          ttl: const Duration(seconds: 60),
          etag: 'E2',
          lastModified: 'LM2',
          mustValidate: false);
      // allow async write to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final hit = store.getWithMeta<Map<String, dynamic>>(
          key, const Duration(seconds: 60));
      expect(hit, isNotNull);
      expect(hit!.etag, 'E2');
      expect(hit.lastModified, 'LM2');
      expect(hit.mustValidate, isFalse);
      // Update meta
      store.updateMeta(key,
          ttl: const Duration(seconds: 120),
          etag: 'E3',
          lastModified: 'LM3',
          mustValidate: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final hit2 = store.getWithMeta<Map<String, dynamic>>(
          key, const Duration(seconds: 120));
      expect(hit2, isNotNull);
      expect(hit2!.etag, 'E3');
      expect(hit2.lastModified, 'LM3');
      expect(hit2.mustValidate, isTrue);
    });
  });

  group('CompositeCacheStore', () {
    test('promotes file hit into memory', () async {
      final mem = InMemoryCacheStore();
      final dir = await Directory.systemTemp.createTemp('sonic_test_cmp_');
      addTearDown(() async => dir.delete(recursive: true));
      final file = FileCacheStore(directoryPath: dir.path);
      final composite = CompositeCacheStore(memory: mem, file: file);
      final key = mem.makeKey('GET', '/c', null, null);
      file.put(key, 'x',
          etag: 'E',
          lastModified: 'LM',
          mustValidate: false,
          ttl: const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mem.getWithMeta<String>(key, const Duration(seconds: 10)), isNull);
      final hit =
          composite.getWithMeta<String>(key, const Duration(seconds: 10));
      expect(hit, isNotNull);
      expect(hit!.etag, 'E');
      // Now memory should have it
      final memHit = mem.getWithMeta<String>(key, const Duration(seconds: 10));
      expect(memHit, isNotNull);
      expect(memHit!.lastModified, 'LM');
    });
  });
}
