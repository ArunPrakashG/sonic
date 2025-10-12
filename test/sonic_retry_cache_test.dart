import 'dart:async';

import 'package:dio/dio.dart';
import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<dynamic>? cancelFuture) async {
    return await handler(options);
  }
}

ResponseBody _jsonBody(String json,
    {int status = 200, Map<String, List<String>>? headers}) {
  return ResponseBody.fromString(
    json,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...?headers,
    },
  );
}

void main() {
  group('Retry and cache', () {
    test('retries on 503 and succeeds', () async {
      var count = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'))
        ..httpClientAdapter = _FakeAdapter((options) async {
          count++;
          if (count < 3) {
            return _jsonBody('{"message":"unavailable"}', status: 503);
          }
          return _jsonBody('{"id":1}');
        });

      final sonic = Sonic(
          baseConfiguration: const BaseConfiguration(
              baseUrl: 'https://example.com',
              retryOptions: RetryOptions(maxAttempts: 3)),
          client: dio);
      // Register a trivial decoder
      sonic.registerType<Map<String, dynamic>>(
          decoder: (j) => j as Map<String, dynamic>);

      final res =
          await sonic.create<Map<String, dynamic>>(url: '/foo').get().execute();
      expect(res.isSuccess, isTrue);
      expect(count, equals(3));
      expect(res.data!['id'], 1);
    });

    test('in-memory cache returns cached response', () async {
      var count = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'))
        ..httpClientAdapter = _FakeAdapter((options) async {
          count++;
          return _jsonBody('{"id":42}');
        });

      final sonic = Sonic(
          baseConfiguration:
              const BaseConfiguration(baseUrl: 'https://example.com'));
      sonic.initialize(client: dio);
      sonic.registerType<Map<String, dynamic>>(
          decoder: (j) => j as Map<String, dynamic>);

      final req = sonic.create<Map<String, dynamic>>(url: '/foo').get().cache();
      final res1 = await req.execute();
      final res2 = await req.execute();

      expect(res1.isSuccess, isTrue);
      expect(res2.isSuccess, isTrue);
      expect(count, equals(1));
      expect(res2.data!['id'], 42);
    });

    test('deduplicates in-flight GET requests', () async {
      var count = 0;
      final completer = Completer<void>();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'))
        ..httpClientAdapter = _FakeAdapter((options) async {
          count++;
          if (!completer.isCompleted) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          return _jsonBody('{"v":1}');
        });

      final sonic = Sonic(
          baseConfiguration:
              const BaseConfiguration(baseUrl: 'https://example.com'));
      sonic.initialize(client: dio);
      sonic.registerType<Map<String, dynamic>>(
          decoder: (j) => j as Map<String, dynamic>);

      final req = sonic
          .create<Map<String, dynamic>>(url: '/bar')
          .get()
          .deduplicate(enabled: true);
      final f1 = req.execute();
      final f2 = req.execute();

      final r = await Future.wait([f1, f2]);
      expect(r[0].isSuccess, isTrue);
      expect(r[1].isSuccess, isTrue);
      expect(count, equals(1));
      completer.complete();
    });
  });

  group('ETag and SWR', () {
    test('uses If-None-Match and handles 304 by serving cache', () async {
      var call = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'))
        ..httpClientAdapter = _FakeAdapter((options) async {
          call++;
          if (call == 1) {
            return _jsonBody('{"id":7}', headers: {
              'etag': ['abc']
            });
          } else {
            // Expect If-None-Match header on second call
            expect(options.headers['If-None-Match'], 'abc');
            return ResponseBody.fromString('', 304, headers: {
              'etag': ['abc'],
            });
          }
        });

      final sonic = Sonic(
          baseConfiguration: const BaseConfiguration(
              baseUrl: 'https://example.com',
              cachePolicy: CachePolicy(
                  enabled: true,
                  ttl: Duration(milliseconds: 1),
                  staleWhileRevalidate: Duration(seconds: 5))))
        ..initialize(client: dio);
      sonic.registerType<Map<String, dynamic>>(
          decoder: (j) => j as Map<String, dynamic>);

      // First call: populate cache
      final res1 = await sonic
          .create<Map<String, dynamic>>(url: '/e')
          .get()
          .cache()
          .execute();
      expect(res1.isSuccess, isTrue);
      expect(res1.data!['id'], 7);

      // Wait for TTL to expire but within SWR
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Second call: should return cached immediately and background refresh sends If-None-Match and receives 304
      final res2 = await sonic
          .create<Map<String, dynamic>>(url: '/e')
          .get()
          .cache()
          .execute();
      expect(res2.isSuccess, isTrue);
      expect(res2.data!['id'], 7);
    });
  });
}
