import 'dart:async';
import 'dart:io' show HttpDate;

import 'package:dio/dio.dart';
import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<dynamic>? cancelFuture) async {
    return handler(options);
  }
}

ResponseBody _json(Map<String, dynamic> body,
    {int status = 200, Map<String, List<String>>? headers}) {
  final h = <String, List<String>>{
    'content-type': ['application/json']
  };
  if (headers != null) {
    h.addAll(headers);
  }
  return ResponseBody.fromString('{"x":${body['x']}}', status, headers: h);
}

void main() {
  group('Sonic caching and validation', () {
    test('fresh cache hit returns without network', () async {
      final dio = Dio();
      var calls = 0;
      dio.httpClientAdapter = _MockAdapter((opts) async {
        calls++;
        return _json({
          'x': 1
        }, headers: {
          'etag': ['E1'],
          'cache-control': ['max-age=60'],
        });
      });
      final sonic = Sonic.initialize(
        baseConfiguration: const BaseConfiguration(
            baseUrl: '', cachePolicy: CachePolicy(enabled: true)),
        client: dio,
      );

      final r1 = await sonic
          .create<Map<String, dynamic>>(url: '/a')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      expect(r1.isSuccess, isTrue);
      expect(calls, 1);
      final r2 = await sonic
          .create<Map<String, dynamic>>(url: '/a')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      expect(r2.isSuccess, isTrue);
      expect(calls, 1, reason: 'should hit cache on second call');
      expect(r2.extra?['cacheEvent'], 'hit');
      expect(r2.extra?['cache'], 'store');
      expect(r2.extra?['durationMs'], isA<int>());
    });

    test('SWR serves stale and refreshes in background (304 path)', () async {
      final dio = Dio();
      var step = 0;
      dio.httpClientAdapter = _MockAdapter((opts) async {
        if (step == 0) {
          step++;
          return _json({
            'x': 1
          }, headers: {
            'etag': ['E2'],
            'cache-control': ['max-age=0'],
          });
        }
        // Background refresh should send If-None-Match
        expect(opts.headers['If-None-Match'], 'E2');
        return _json({'x': 1},
            status: 304,
            headers: {
              'etag': ['E2'],
              'cache-control': ['max-age=30'],
            });
      });
      final sonic = Sonic.initialize(
        baseConfiguration: const BaseConfiguration(
          baseUrl: '',
          cachePolicy: CachePolicy(
              enabled: true,
              ttl: Duration(milliseconds: 1),
              staleWhileRevalidate: Duration(seconds: 1)),
        ),
        client: dio,
      );

      // Seed
      await sonic
          .create<Map<String, dynamic>>(url: '/a')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      // Wait for TTL to expire
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // Call again to trigger stale-while-revalidate
      final r2 = await sonic
          .create<Map<String, dynamic>>(url: '/a')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      expect(r2.isSuccess, isTrue);
      // Give time to background refresh to run
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(r2.extra?['cacheEvent'], 'stale');
      expect(r2.extra?['cache'], 'store');
    });

    test('must-revalidate enforces synchronous validation', () async {
      final dio = Dio();
      var calls = 0;
      dio.httpClientAdapter = _MockAdapter((opts) async {
        calls++;
        if (calls == 1) {
          return _json({
            'x': 1
          }, headers: {
            'etag': ['E3'],
            'cache-control': ['must-revalidate'],
          });
        }
        expect(opts.headers['If-None-Match'], 'E3');
        return _json({'x': 1},
            status: 304,
            headers: {
              'etag': ['E3'],
              'cache-control': ['max-age=10'],
            });
      });
      final sonic = Sonic.initialize(
        baseConfiguration: const BaseConfiguration(
            baseUrl: '', cachePolicy: CachePolicy(enabled: true)),
        client: dio,
      );

      await sonic
          .create<Map<String, dynamic>>(url: '/a')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      // Next call will validate synchronously due to must-revalidate
      final r2 = await sonic
          .create<Map<String, dynamic>>(url: '/a')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      expect(calls, 2);
      expect(r2.isSuccess, isTrue);
      expect(r2.extra?['cacheEvent'], 'validated');
      expect(r2.extra?['cache'], 'validated-304');
    });
  });

  group('Deduplication and retries and hooks', () {
    test('deduplicates concurrent GETs', () async {
      final dio = Dio();
      var calls = 0;
      final completer = Completer<void>();
      dio.httpClientAdapter = _MockAdapter((opts) async {
        calls++;
        await completer.future;
        return _json({
          'x': 1
        }, headers: {
          'cache-control': ['max-age=60'],
        });
      });
      final sonic = Sonic.initialize(
        baseConfiguration: const BaseConfiguration(
            baseUrl: '', cachePolicy: CachePolicy(enabled: true)),
        client: dio,
      );
      final f1 = sonic
          .create<Map<String, dynamic>>(url: '/d')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      final f2 = sonic
          .create<Map<String, dynamic>>(url: '/d')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      completer.complete();
      final r = await Future.wait([f1, f2]);
      expect(r.every((e) => e.isSuccess), isTrue);
      expect(calls, 1);
      // Both responses should indicate deduplication was enabled
      expect(r[0].extra?['deduplicated'], isTrue);
      expect(r[1].extra?['deduplicated'], isTrue);
    });

    test('retries on 503 obeying maxAttempts', () async {
      final dio = Dio();
      var calls = 0;
      dio.httpClientAdapter = _MockAdapter((opts) async {
        calls++;
        if (calls < 3) {
          return _json({'x': 0}, status: 503);
        }
        return _json({'x': 1});
      });
      final sonic = Sonic.initialize(
        baseConfiguration: const BaseConfiguration(
            baseUrl: '', retryOptions: RetryOptions(maxAttempts: 3)),
        client: dio,
      );
      final r = await sonic
          .create<Map<String, dynamic>>(url: '/r')
          .get()
          .asRawRequest()
          .execute();
      expect(r.isSuccess, isTrue);
      expect(calls, 3);
      final delays = r.extra?['retryDelaysMs'] as List<dynamic>?;
      expect(delays, isNotNull);
      expect(delays!.length, greaterThanOrEqualTo(1));
      expect(delays.first, isA<int>());
    });

    test('hooks fire for request/response', () async {
      final dio = Dio();
      var onReq = false;
      var onRes = false;
      dio.httpClientAdapter = _MockAdapter((opts) async => _json({'x': 1}));
      final sonic = Sonic.initialize(
        baseConfiguration: BaseConfiguration(
          baseUrl: '',
          onRequest: (_) => onReq = true,
          onResponse: (_) => onRes = true,
        ),
        client: dio,
      );
      final r = await sonic
          .create<Map<String, dynamic>>(url: '/h')
          .get()
          .asRawRequest()
          .execute();
      expect(r.isSuccess, isTrue);
      expect(onReq, isTrue);
      expect(onRes, isTrue);
    });
  });

  group('AuthRefreshInterceptor', () {
    test('401 triggers refresh and retried request contains Authorization',
        () async {
      final dio = Dio();
      String? lastAuthHeader;
      dio.httpClientAdapter = _MockAdapter((opts) async {
        lastAuthHeader = opts.headers['Authorization'] as String?;
        if (lastAuthHeader == null) {
          return _json({'x': 0}, status: 401);
        }
        return _json({'x': 1});
      });
      final sonic = Sonic.initialize(
        baseConfiguration: const BaseConfiguration(baseUrl: ''),
        client: dio,
      );
      sonic.addInterceptor(AuthRefreshInterceptor(
        handler: DefaultAuthRefreshHandler(
          shouldRefresh: (err) => err.response?.statusCode == 401,
          refresh: () async => 'tok123',
          setAuthHeader: (req, token) =>
              req.headers['Authorization'] = 'Bearer $token',
        ),
      ));

      final r = await sonic
          .create<Map<String, dynamic>>(url: '/auth')
          .get()
          .asRawRequest()
          .execute();
      expect(r.isSuccess, isTrue);
      expect(lastAuthHeader, 'Bearer tok123');
    });
  });

  group('Expires-only caching', () {
    test('falls back to Expires header for TTL when max-age is absent',
        () async {
      final dio = Dio();
      var calls = 0;
      dio.httpClientAdapter = _MockAdapter((opts) async {
        calls++;
        final expires =
            HttpDate.format(DateTime.now().add(const Duration(seconds: 5)));
        return _json({
          'x': 1
        }, headers: {
          'expires': [expires],
        });
      });
      final sonic = Sonic.initialize(
        baseConfiguration: const BaseConfiguration(
            baseUrl: '', cachePolicy: CachePolicy(enabled: true)),
        client: dio,
      );
      final r1 = await sonic
          .create<Map<String, dynamic>>(url: '/exp')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      expect(r1.isSuccess, isTrue);
      final r2 = await sonic
          .create<Map<String, dynamic>>(url: '/exp')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      expect(r2.isSuccess, isTrue);
      expect(calls, 1, reason: 'should use cache based on Expires');
      expect(r2.extra?['cacheEvent'], 'hit');
      expect(r2.extra?['cache'], 'store');
    });
  });

  group('Last-Modified validation', () {
    test(
        'SWR background refresh uses If-Modified-Since when only Last-Modified present',
        () async {
      final dio = Dio();
      var step = 0;
      final lastMod = HttpDate.format(DateTime.now().toUtc());
      dio.httpClientAdapter = _MockAdapter((opts) async {
        if (step == 0) {
          step++;
          return _json({
            'x': 1
          }, headers: {
            'last-modified': [lastMod],
            'cache-control': ['max-age=0'],
          });
        }
        // Background refresh should send If-Modified-Since
        expect(opts.headers['If-Modified-Since'], lastMod);
        return _json({'x': 1},
            status: 304,
            headers: {
              'last-modified': [lastMod],
              'cache-control': ['max-age=20'],
            });
      });
      final sonic = Sonic.initialize(
        baseConfiguration: const BaseConfiguration(
          baseUrl: '',
          cachePolicy: CachePolicy(
              enabled: true,
              ttl: Duration(milliseconds: 1),
              staleWhileRevalidate: Duration(seconds: 1)),
        ),
        client: dio,
      );

      await sonic
          .create<Map<String, dynamic>>(url: '/lm')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final r2 = await sonic
          .create<Map<String, dynamic>>(url: '/lm')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      expect(r2.isSuccess, isTrue);
      expect(r2.extra?['cacheEvent'], 'stale');
    });

    test(
        'must-revalidate synchronous validation uses If-Modified-Since when only Last-Modified present',
        () async {
      final dio = Dio();
      final lastMod = HttpDate.format(DateTime.now().toUtc());
      var calls = 0;
      dio.httpClientAdapter = _MockAdapter((opts) async {
        calls++;
        if (calls == 1) {
          return _json({
            'x': 1
          }, headers: {
            'last-modified': [lastMod],
            'cache-control': ['must-revalidate'],
          });
        }
        expect(opts.headers['If-Modified-Since'], lastMod);
        return _json({'x': 1},
            status: 304,
            headers: {
              'last-modified': [lastMod],
              'cache-control': ['max-age=15'],
            });
      });
      final sonic = Sonic.initialize(
        baseConfiguration: const BaseConfiguration(
            baseUrl: '', cachePolicy: CachePolicy(enabled: true)),
        client: dio,
      );

      await sonic
          .create<Map<String, dynamic>>(url: '/lm2')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      final r2 = await sonic
          .create<Map<String, dynamic>>(url: '/lm2')
          .get()
          .cache()
          .asRawRequest()
          .execute();
      expect(r2.isSuccess, isTrue);
      expect(calls, 2);
      expect(r2.extra?['cacheEvent'], 'validated');
      expect(r2.extra?['cache'], 'validated-304');
    });
  });

  group('Error hooks', () {
    test('onError hook is called once on 500 without retries', () async {
      final dio = Dio();
      var errorCalls = 0;
      dynamic lastError;
      dio.httpClientAdapter =
          _MockAdapter((opts) async => _json({'x': 0}, status: 500));
      final sonic = Sonic.initialize(
        baseConfiguration: BaseConfiguration(
          baseUrl: '',
          retryOptions: const RetryOptions(maxAttempts: 1),
          onError: (e) {
            errorCalls++;
            lastError = e;
          },
        ),
        client: dio,
      );

      final r = await sonic
          .create<Map<String, dynamic>>(url: '/err')
          .get()
          .asRawRequest()
          .execute();
      expect(r.isSuccess, isFalse);
      expect(errorCalls, 1);
      expect(lastError, isNotNull);
      expect(lastError, isA<DioException>());
      final de = lastError as DioException;
      expect(de.response?.statusCode, 500);
    });
  });
}
