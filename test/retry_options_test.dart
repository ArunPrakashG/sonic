import 'package:dio/dio.dart';
import 'package:sonic/src/retry_options.dart';
import 'package:test/test.dart';

void main() {
  group('RetryOptions', () {
    test('shouldAttemptRetry honors status codes and methods', () {
      const ro = RetryOptions(maxAttempts: 3, retryOnStatusCodes: {503});
      final res =
          Response(requestOptions: RequestOptions(path: '/'), statusCode: 503);
      expect(ro.shouldAttemptRetry(attempt: 1, method: 'GET', response: res),
          isTrue);
      expect(ro.shouldAttemptRetry(attempt: 3, method: 'GET', response: res),
          isFalse);
      expect(ro.shouldAttemptRetry(attempt: 1, method: 'POST', response: res),
          isFalse);
    });

    test('shouldAttemptRetry honors error types', () {
      const ro = RetryOptions(maxAttempts: 2);
      final err = DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionTimeout);
      expect(
          ro.shouldAttemptRetry(attempt: 1, method: 'GET', error: err), isTrue);
    });

    test('computeDelay uses Retry-After when present', () {
      const ro = RetryOptions(
          maxAttempts: 2, jitter: false, exponentialBackoff: false);
      final res = Response(
        requestOptions: RequestOptions(path: '/'),
        statusCode: 503,
        headers: Headers.fromMap({
          'retry-after': ['2']
        }),
      );
      final delay = ro.computeDelay(1, response: res);
      expect(delay.inSeconds, 2);
    });

    test('computeDelay exponential backoff and jitter', () {
      const ro = RetryOptions(
          maxAttempts: 4,
          baseDelay: Duration(milliseconds: 100),
          maxDelay: Duration(seconds: 10),
          jitter: false);
      final d1 = ro.computeDelay(1);
      final d2 = ro.computeDelay(2);
      final d3 = ro.computeDelay(3);
      expect(d1.inMilliseconds, 100);
      expect(d2.inMilliseconds, 200);
      expect(d3.inMilliseconds, 400);
    });
  });
}
