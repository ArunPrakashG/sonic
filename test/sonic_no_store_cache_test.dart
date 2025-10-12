import 'package:dio/dio.dart';
import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future? cancelFuture) {
    return handler(options);
  }
}

void main() {
  test('Cache-Control: no-store bypasses cache entirely', () async {
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((o) async {
        calls++;
        return ResponseBody.fromString('{"ok":true}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          'cache-control': ['no-store'],
        });
      });
    final sonic = Sonic.initialize(
      baseConfiguration: const BaseConfiguration(baseUrl: ''),
      client: dio,
    );

    final req = sonic
        .create<Map<String, dynamic>>(url: '/ns')
        .get()
        .cache()
        .asRawRequest();
    final r1 = await req.execute();
    final r2 = await req.execute();
    expect(r1.isSuccess, isTrue);
    expect(r2.isSuccess, isTrue);
    expect(calls, 2, reason: 'no-store should prevent caching');
  });
}
