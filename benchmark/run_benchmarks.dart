import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart' as dio;
import 'package:http/http.dart' as http;
import 'package:sonic/sonic.dart';

import 'server.dart';

class Stats {
  Stats(this.samples);
  final List<int> samples;
  double get avg =>
      samples.isEmpty ? 0 : samples.reduce((a, b) => a + b) / samples.length;
  int get p90 => _percentile(0.90);
  int get p99 => _percentile(0.99);
  int _percentile(double p) {
    if (samples.isEmpty) return 0;
    final s = [...samples]..sort();
    final idx = min(s.length - 1, (s.length * p).floor());
    return s[idx];
  }
}

Future<int> time(Future<void> Function() f) async {
  final t0 = DateTime.now();
  await f();
  return DateTime.now().difference(t0).inMilliseconds;
}

Future<void> main() async {
  final server = await startServer();
  final base = 'http://${server.address.host}:${server.port}';
  print('Server at $base');

  final sonic =
      Sonic.initialize(baseConfiguration: BaseConfiguration(baseUrl: base));
  final d = dio.Dio(dio.BaseOptions(baseUrl: base));

  Future<void> warmup() async {
    await http.get(Uri.parse('$base/json/small'));
    await d.get('/json/small');
    await sonic.create<Map<String, dynamic>>(url: '/json/small').execute();
  }

  await warmup();

  // Run a micro-benchmark with n iterations (default 25 for more stable stats)
  Future<Stats> bench(String name, Future<void> Function() f,
      {int n = 25}) async {
    final samples = <int>[];
    for (var i = 0; i < n; i++) {
      samples.add(await time(f));
    }
    print(
        '$name avg=${Stats(samples).avg.toStringAsFixed(1)}ms p90=${Stats(samples).p90}ms p99=${Stats(samples).p99}ms');
    return Stats(samples);
  }

  final results = <String, Map<String, Stats>>{};

  // GET JSON small
  results['GET json (1KB)'] = {
    'http': await bench('http small', () async {
      final r = await http.get(Uri.parse('$base/json/small'));
      jsonDecode(r.body);
    }),
    'dio': await bench('dio small', () async {
      final r = await d.get('/json/small');
      r.data;
    }),
    'sonic': await bench('sonic small', () async {
      await sonic
          .create<Map<String, dynamic>>(url: '/json/small')
          .withDecoder((j) => j as Map<String, dynamic>)
          .execute();
    }),
  };

  // GET JSON medium
  results['GET json (50KB)'] = {
    'http': await bench('http medium', () async {
      final r = await http.get(Uri.parse('$base/json/medium'));
      jsonDecode(r.body);
    }),
    'dio': await bench('dio medium', () async {
      final r = await d.get('/json/medium');
      r.data;
    }),
    'sonic': await bench('sonic medium', () async {
      await sonic
          .create<Map<String, dynamic>>(url: '/json/medium')
          .withDecoder((j) => j as Map<String, dynamic>)
          .execute();
    }),
  };

  // GET bytes 100KB
  results['GET bytes (100KB)'] = {
    'http': await bench('http bytes', () async {
      final r = await http.get(Uri.parse('$base/bytes/100k'));
      r.bodyBytes.length;
    }),
    'dio': await bench('dio bytes', () async {
      final r = await d.get('/bytes/100k',
          options: dio.Options(responseType: dio.ResponseType.bytes));
      (r.data as List<int>).length;
    }),
    'sonic': await bench('sonic bytes', () async {
      await sonic
          .create<List<int>>(url: '/bytes/100k', rawRequest: true)
          .withResponseType(ResponseType.bytes)
          .execute();
    }),
  };

  // GET JSON large (~1MB)
  results['GET json (1MB)'] = {
    'http': await bench('http large', () async {
      final r = await http.get(Uri.parse('$base/json/large'));
      jsonDecode(r.body);
    }),
    'dio': await bench('dio large', () async {
      final r = await d.get('/json/large');
      r.data;
    }),
    'sonic': await bench('sonic large', () async {
      await sonic
          .create<Map<String, dynamic>>(url: '/json/large')
          .withDecoder((j) => j as Map<String, dynamic>)
          .execute();
    }),
  };

  // Streaming download (5MB)
  results['stream download (5MB)'] = {
    'http': await bench('http stream 5MB', () async {
      final req = await HttpClient().getUrl(Uri.parse('$base/stream/5mb'));
      final res = await req.close();
      await res.drain();
    }),
    'dio': await bench('dio stream 5MB', () async {
      final res = await d.get<dio.ResponseBody>('/stream/5mb',
          options: dio.Options(responseType: dio.ResponseType.stream));
      await res.data!.stream.drain();
    }),
    'sonic': await bench('sonic stream 5MB', () async {
      final r = await sonic
          .create<Stream<List<int>>>(url: '/stream/5mb')
          .withResponseType(ResponseType.stream)
          .withDecoder((s) => (s as dio.ResponseBody).stream)
          .execute();
      await r.data!.drain();
    }),
  };

  // Multipart upload (~1MB)
  final uploadBytes = List<int>.filled(1024 * 1024, 3);
  results['upload (1MB bytes)'] = {
    'dio': await bench('dio upload', () async {
      await d.post('/upload', data: Stream.fromIterable([uploadBytes]));
    }),
    'sonic': await bench('sonic upload', () async {
      await sonic
          .create<Map<String, dynamic>>(url: '/upload')
          .post()
          .withDecoder((j) => j as Map<String, dynamic>)
          .withBinaryBody(uploadBytes)
          .execute();
    }),
  };

  // Parallel GET x 20 without dedup
  // NOTE: For Sonic, explicitly disable deduplication to make this fair.
  results['parallel x20 (no dedup)'] = {
    'dio': await bench('dio parallel', () async {
      await Future.wait(List.generate(20, (_) => d.get('/json/small')));
    }),
    'sonic': await bench('sonic parallel', () async {
      await Future.wait(List.generate(
          20,
          (_) => sonic
              .create<Map<String, dynamic>>(url: '/json/small')
              .withDecoder((j) => j as Map<String, dynamic>)
              .deduplicate(enabled: false)
              .execute()));
    }),
  };

  // Parallel GET x 2 without dedup
  results['parallel x2 (no dedup)'] = {
    'dio': await bench('dio parallel x2', () async {
      await Future.wait(List.generate(2, (_) => d.get('/json/small')));
    }),
    'sonic': await bench('sonic parallel x2', () async {
      await Future.wait(List.generate(
          2,
          (_) => sonic
              .create<Map<String, dynamic>>(url: '/json/small')
              .withDecoder((j) => j as Map<String, dynamic>)
              .deduplicate(enabled: false)
              .execute()));
    }),
  };

  // Parallel GET x 20 with dedup (Sonic only)
  results['parallel x20 (dedup on)'] = {
    'sonic': await bench('sonic dedup parallel', () async {
      final req = sonic
          .create<Map<String, dynamic>>(url: '/json/small')
          .withDecoder((j) => j as Map<String, dynamic>)
          .deduplicate();
      await Future.wait(List.generate(20, (_) => req.execute()));
    }),
  };

  // Retry on 500 (3 attempts)
  results['retry (3 attempts)'] = {
    'dio': await bench('dio retry', () async {
      var attempt = 0;
      try {
        await d.get('/retry',
            options:
                dio.Options(headers: {'x-attempt': (++attempt).toString()}));
      } catch (_) {}
    }),
    'sonic': await bench('sonic retry', () async {
      var attempt = 0;
      await sonic
          .create<Map<String, dynamic>>(url: '/retry')
          .withDecoder((j) => j as Map<String, dynamic>)
          .withHeader('x-attempt', (++attempt).toString())
          .withRetryOptions(const RetryOptions(maxAttempts: 3))
          .execute();
    }),
  };

  // Dump JSON to stdout for wiki formatting; keep it simple
  final out = results.map((scenario, byLib) => MapEntry(
      scenario,
      byLib.map((lib, s) => MapEntry(lib, {
            'avgMs': s.avg,
            'p90Ms': s.p90,
            'p99Ms': s.p99,
          }))));
  final jsonOut = const JsonEncoder.withIndent('  ').convert(out);
  final osTag = Platform.operatingSystem;
  final file = File('benchmark/results-$osTag.json');
  await file.create(recursive: true);
  await file.writeAsString(jsonOut);
  print('\nSaved results to ${file.path}');

  await server.close();
}
