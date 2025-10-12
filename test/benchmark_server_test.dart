import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/server.dart' as bench;

void main() {
  group('benchmark server endpoints', () {
    test('json small endpoint returns expected shape', () async {
      final server = await bench.startServer();
      final base = 'http://${server.address.host}:${server.port}';
      final resp = await HttpClient().getUrl(Uri.parse('$base/json/small'));
      final res = await resp.close();
      expect(res.statusCode, 200);
      final body = await utf8.decodeStream(res);
      final obj = jsonDecode(body) as Map<String, dynamic>;
      expect(obj['name'], 'small');
      expect((obj['items'] as List).length, 10);
      await server.close();
    });

    test('json medium endpoint returns expected size', () async {
      final server = await bench.startServer();
      final base = 'http://${server.address.host}:${server.port}';
      final res =
          await (await HttpClient().getUrl(Uri.parse('$base/json/medium')))
              .close();
      expect(res.statusCode, 200);
      final obj =
          jsonDecode(await utf8.decodeStream(res)) as Map<String, dynamic>;
      expect(obj['name'], 'medium');
      expect((obj['items'] as List).length, 2000);
      await server.close();
    });

    test('bytes endpoint returns 100k bytes', () async {
      final server = await bench.startServer();
      final base = 'http://${server.address.host}:${server.port}';
      final res =
          await (await HttpClient().getUrl(Uri.parse('$base/bytes/100k')))
              .close();
      expect(res.statusCode, 200);
      final bytes =
          await res.fold<List<int>>(<int>[], (acc, data) => acc..addAll(data));
      expect(bytes.length, 100 * 1024);
      await server.close();
    });

    test('retry endpoint returns 500 then 200 after attempts', () async {
      final server = await bench.startServer();
      final base = 'http://${server.address.host}:${server.port}';
      final client = HttpClient();
      // First two attempts with x-attempt: 1 and 2 should 500; 3 should succeed
      for (var a = 1; a <= 2; a++) {
        final req = await client.getUrl(Uri.parse('$base/retry'));
        req.headers.add('x-attempt', a.toString());
        final res = await req.close();
        expect(res.statusCode, 500);
      }
      final req3 = await client.getUrl(Uri.parse('$base/retry'));
      req3.headers.add('x-attempt', '3');
      final res3 = await req3.close();
      expect(res3.statusCode, 200);
      await server.close();
    });

    test('json large endpoint returns sizable payload', () async {
      final server = await bench.startServer();
      final base = 'http://${server.address.host}:${server.port}';
      final res =
          await (await HttpClient().getUrl(Uri.parse('$base/json/large')))
              .close();
      expect(res.statusCode, 200);
      final body = await utf8.decodeStream(res);
      final obj = jsonDecode(body) as Map<String, dynamic>;
      expect(obj['name'], 'large');
      expect((obj['items'] as List).length, greaterThan(10000));
      await server.close();
    });

    test('stream 5mb endpoint streams data', () async {
      final server = await bench.startServer();
      final base = 'http://${server.address.host}:${server.port}';
      final res =
          await (await HttpClient().getUrl(Uri.parse('$base/stream/5mb')))
              .close();
      expect(res.statusCode, 200);
      var total = 0;
      await for (final chunk in res) {
        total += chunk.length;
      }
      expect(total, 5 * 1024 * 1024);
      await server.close();
    });

    test('upload endpoint echoes byte count', () async {
      final server = await bench.startServer();
      final base = 'http://${server.address.host}:${server.port}';
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse('$base/upload'));
      final bytes = List<int>.filled(1024 * 1024, 7);
      req.add(bytes);
      final res = await req.close();
      expect(res.statusCode, 200);
      final map =
          jsonDecode(await utf8.decodeStream(res)) as Map<String, dynamic>;
      expect(map['ok'], true);
      expect(map['bytes'], 1024 * 1024);
      await server.close();
    });
  });
}
