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
  test('pluck disables GET cache to avoid shape mismatch', () async {
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((o) async {
        calls++;
        return ResponseBody.fromString('{"data":{"value":42}}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
      });
    final sonic = Sonic.initialize(
      baseConfiguration: const BaseConfiguration(baseUrl: ''),
      client: dio,
    );

    final req = sonic
        .create<int>(url: '/pluck')
        .get()
        .pluck('data.value')
        .withDecoder((j) => j as int)
        .cache();

    final r1 = await req.execute();
    final r2 = await req.execute();

    expect(r1.isSuccess, isTrue);
    expect(r2.isSuccess, isTrue);
    expect(calls, 2,
        reason: 'pluck must disable cache so both calls hit network');
  });
}
