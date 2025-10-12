import 'package:dio/dio.dart';
import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

void main() {
  test('parseLinkHeader parses next/prev', () {
    // Minimal Headers shim via Dio
    final h = Headers.fromMap({
      'link': [
        '<https://api.example.com/x?page=2>; rel="next", <https://api.example.com/x?page=0>; rel="prev"'
      ]
    });
    final parsed = parseLinkHeader(h);
    expect(parsed['next'], contains('page=2'));
    expect(parsed['prev'], contains('page=0'));
  });
}
