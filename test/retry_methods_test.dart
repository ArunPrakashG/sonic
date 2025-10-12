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
      Stream<List<int>>? requestStream, Future? cancelFuture) async {
    return handler(options);
  }
}

void main() {
  test('POST is not retried by default retry options', () async {
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((o) async {
        calls++;
        return ResponseBody.fromString('fail', 503);
      });

    final sonic = Sonic.initialize(
      baseConfiguration: const BaseConfiguration(baseUrl: ''),
      client: dio,
    );

    final res = await sonic
        .create<Map<String, dynamic>>(url: '/x')
        .post()
        .asRawRequest()
        .execute();
    expect(res.isSuccess, isFalse);
    expect(calls, 1, reason: 'non-idempotent methods should not retry');
  });
}
