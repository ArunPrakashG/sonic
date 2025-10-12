import 'dart:convert';
import 'dart:io';

Future<HttpServer> startServer({int port = 0}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  server.listen((req) async {
    final path = req.uri.path;
    if (path == '/json/small') {
      final obj = {
        'id': 1,
        'name': 'small',
        'items': List.generate(10, (i) => {'i': i, 'v': i * 2}),
      };
      final body = jsonEncode(obj);
      req.response.headers.contentType = ContentType.json;
      req.response.write(body);
      await req.response.close();
      return;
    }
    if (path == '/json/medium') {
      final items = List.generate(2000, (i) => {'i': i, 'v': i * 2});
      final obj = {'id': 2, 'name': 'medium', 'items': items};
      final body = jsonEncode(obj);
      req.response.headers.contentType = ContentType.json;
      req.response.write(body);
      await req.response.close();
      return;
    }
    if (path == '/bytes/100k') {
      final bytes = List<int>.filled(100 * 1024, 1);
      req.response.headers.contentType = ContentType.binary;
      req.response.add(bytes);
      await req.response.close();
      return;
    }
    if (path == '/json/large') {
      // ~1MB JSON: array of objects
      final items =
          List.generate(15000, (i) => {'i': i, 'v': i * 2, 's': 'x' * 20});
      final body = jsonEncode({'id': 3, 'name': 'large', 'items': items});
      req.response.headers.contentType = ContentType.json;
      req.response.write(body);
      await req.response.close();
      return;
    }
    if (path == '/stream/5mb') {
      // Chunked 5MB binary stream
      req.response.headers.contentType = ContentType.binary;
      const total = 5 * 1024 * 1024;
      const chunk = 32 * 1024;
      var sent = 0;
      while (sent < total) {
        final size = (total - sent) < chunk ? (total - sent) : chunk;
        req.response.add(List<int>.filled(size, 2));
        await req.response.flush();
        sent += size;
      }
      await req.response.close();
      return;
    }
    if (path == '/upload' && req.method == 'POST') {
      // Accept body and return JSON with total bytes received
      var total = 0;
      await for (final data in req) {
        total += data.length;
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'ok': true, 'bytes': total}));
      await req.response.close();
      return;
    }
    if (path == '/retry') {
      final attempt = req.headers.value('x-attempt');
      final a = int.tryParse(attempt ?? '1') ?? 1;
      if (a < 3) {
        req.response.statusCode = 500;
        await req.response.close();
        return;
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"ok":true}');
      await req.response.close();
      return;
    }
    req.response.statusCode = 404;
    await req.response.close();
  });
  return server;
}
