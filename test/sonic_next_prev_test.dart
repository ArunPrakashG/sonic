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
  test('SonicResponse.nextPage/prevPage build correct builders and execute',
      () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter((o) async {
        if (o.path.contains('page=2')) {
          return ResponseBody.fromString('[2]', 200, headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
        }
        return ResponseBody.fromString('[1]', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          'link': [
            '<https://example.com/items?page=2>; rel="next", <https://example.com/items?page=0>; rel="prev"'
          ]
        });
      });
    final sonic = Sonic.initialize(
      baseConfiguration: const BaseConfiguration(baseUrl: ''),
      client: dio,
    );

    final res = await sonic
        .create<List<int>>(url: 'https://example.com/items?page=1')
        .withDecoder((j) => (j as List).cast<int>())
        .execute();
    expect(res.data, [1]);

    final next = res.nextPage(sonic);
    final prev = res.prevPage(sonic);
    expect(next, isNotNull);
    expect(prev, isNotNull);

    final nr =
        await next!.withDecoder((j) => (j as List).cast<int>()).execute();
    expect(nr.data, [2]);
  });
}
