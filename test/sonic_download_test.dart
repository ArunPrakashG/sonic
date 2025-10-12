import 'dart:io';

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
  test('downloadTo saves bytes and returns extra info', () async {
    final file = File('${Directory.systemTemp.path}/sonic_download_test.bin');
    if (file.existsSync()) {
      file.deleteSync();
    }

    final dio = Dio()
      ..httpClientAdapter = _Adapter((o) async {
        final bytes = List<int>.generate(16, (i) => i);
        return ResponseBody.fromBytes(bytes, 200, headers: {
          Headers.contentLengthHeader: ['16'],
        });
      });

    final sonic = Sonic.initialize(
      baseConfiguration: const BaseConfiguration(baseUrl: ''),
      client: dio,
    );

    final resp =
        await sonic.create<void>(url: '/download').get().downloadTo(file.path);
    expect(resp.isSuccess, isTrue);
    expect(resp.extra?['downloadPath'], file.path);
    expect(file.existsSync(), isTrue);
    final len = file.lengthSync();
    expect(len, 16);

    file.deleteSync();
  });
}
