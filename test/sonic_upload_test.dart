import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

class _FailingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Immediately fail to avoid real network. This still exercises request building.
    throw DioException(
      requestOptions: options,
      error: 'TestAdapter: no network',
    );
  }
}

void main() {
  test('upload() builds FormData with field and file', () async {
    RequestOptions? captured;
    final config = BaseConfiguration(
      baseUrl: 'https://unit.test',
      onRequest: (opts) => captured = opts,
    );
    final dio = Dio();
    dio.httpClientAdapter = _FailingAdapter();
    final sonic = Sonic(baseConfiguration: config, client: dio);

    final resp = await sonic
        .create<void>(url: '/upload')
        .upload()
        .field('a', '1')
        .fileFromBytes(
          'file',
          Uint8List.fromList([1, 2, 3]),
          filename: 'x.bin',
        )
        .execute();

    // Should have failed due to adapter, but onRequest must have been called.
    expect(resp.statusCode, equals(-1));
    expect(captured, isNotNull);
    expect(captured!.method, equals('post'));
    expect(captured!.data, const TypeMatcher<FormData>());
    final fd = captured!.data as FormData;
    expect(fd.fields.any((e) => e.key == 'a' && e.value == '1'), isTrue);
    expect(fd.files.length, equals(1));
    expect(fd.files.first.key, equals('file'));
    expect(fd.files.first.value.filename, equals('x.bin'));
  });

  test('fields(Map) preserves files and fields', () async {
    RequestOptions? captured;
    final config = BaseConfiguration(
      baseUrl: 'https://unit.test',
      onRequest: (opts) => captured = opts,
    );
    final dio = Dio();
    dio.httpClientAdapter = _FailingAdapter();
    final sonic = Sonic(baseConfiguration: config, client: dio);

    final mf = MultipartFile.fromBytes([0, 1], filename: 'y.txt');

    final resp = await sonic
        .create<void>(url: '/upload')
        .upload()
        .fields({'a': 'b', 'f': mf}).execute();

    expect(resp.statusCode, equals(-1));
    expect(captured, isNotNull);
    expect(captured!.data, const TypeMatcher<FormData>());
    final fd = captured!.data as FormData;
    expect(fd.fields.any((e) => e.key == 'a' && e.value == 'b'), isTrue);
    expect(fd.files.any((e) => e.key == 'f' && e.value.filename == 'y.txt'),
        isTrue);
  });

  test('progress callbacks are assignable via aliases', () async {
    RequestOptions? captured;
    var uploadCalled = false;
    var downloadCalled = false;
    final config = BaseConfiguration(
      baseUrl: 'https://unit.test',
      onRequest: (opts) => captured = opts,
    );
    final dio = Dio();
    dio.httpClientAdapter = _FailingAdapter();
    final sonic = Sonic(baseConfiguration: config, client: dio);

    final resp = await sonic
        .create<void>(url: '/upload')
        .upload()
        .onUploadProgress((_) => uploadCalled = true)
        .onDownloadProgress((_) => downloadCalled = true)
        .field('k', 'v')
        .execute();

    // Even though the request fails, the options are present and callbacks are set on the builder.
    expect(resp.statusCode, equals(-1));
    expect(captured, isNotNull);
    // We can't simulate Dio progress without a real upload; assert that configuration didn't crash.
    expect(uploadCalled, isFalse);
    expect(downloadCalled, isFalse);
  });

  test('fileFromStream accepts factory and length', () async {
    RequestOptions? captured;
    final config = BaseConfiguration(
      baseUrl: 'https://unit.test',
      onRequest: (opts) => captured = opts,
    );
    final dio = Dio();
    dio.httpClientAdapter = _FailingAdapter();
    final sonic = Sonic(baseConfiguration: config, client: dio);

    Stream<List<int>> open() async* {
      yield [1, 2, 3, 4, 5];
    }

    final resp = await sonic
        .create<void>(url: '/upload')
        .upload()
        .fileFromStream('f', open, 5, filename: 's.bin')
        .execute();

    expect(resp.statusCode, equals(-1));
    expect(captured, isNotNull);
    expect(captured!.data, const TypeMatcher<FormData>());
    final fd = captured!.data as FormData;
    expect(fd.files.length, equals(1));
    expect(fd.files.first.value.filename, equals('s.bin'));
  });
}
