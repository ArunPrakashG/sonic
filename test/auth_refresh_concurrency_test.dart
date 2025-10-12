import 'dart:async';

import 'package:dio/dio.dart';
import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future? cancelFuture) async {
    return handler(options);
  }
}

void main() {
  test('AuthRefreshInterceptor deduplicates refresh across concurrent 401s',
      () async {
    final dio = Dio();
    var refreshes = 0;

    dio.httpClientAdapter = _Adapter((opts) async {
      final hasAuth = opts.headers['Authorization'] != null;
      if (hasAuth) {
        return ResponseBody.fromString('{"ok":true}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
      }
      return ResponseBody.fromString('{"err":401}', 401, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    });

    final sonic = Sonic.initialize(
      baseConfiguration: const BaseConfiguration(baseUrl: ''),
      client: dio,
    );

    sonic.addInterceptor(AuthRefreshInterceptor(
      shouldRefresh: (err) => err.response?.statusCode == 401,
      refresh: () async {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 'TOKEN';
      },
      setAuthHeader: (req, token) =>
          req.headers['Authorization'] = 'Bearer $token',
    ));

    final f1 = sonic
        .create<Map<String, dynamic>>(url: '/x')
        .get()
        .asRawRequest()
        .execute();
    final f2 = sonic
        .create<Map<String, dynamic>>(url: '/x')
        .get()
        .asRawRequest()
        .execute();
    final r = await Future.wait([f1, f2]);

    expect(r[0].isSuccess, isTrue);
    expect(r[1].isSuccess, isTrue);
    expect(refreshes, 1, reason: 'only a single refresh should run');
  });
}
