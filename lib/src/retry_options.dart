import 'dart:math';

import 'package:dio/dio.dart';

/// Configuration for automatic retries with backoff and jitter.
class RetryOptions {
  const RetryOptions({
    this.maxAttempts = 0,
    this.baseDelay = const Duration(milliseconds: 200),
    this.maxDelay = const Duration(seconds: 5),
    this.exponentialBackoff = true,
    this.jitter = true,
    this.retryOnStatusCodes = const {429, 502, 503, 504},
    this.retryOnErrorTypes = const {
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.unknown,
    },
    this.retryMethods = const {'GET', 'HEAD', 'PUT', 'DELETE', 'OPTIONS'},
    this.respectRetryAfterHeader = true,
  });

  /// Maximum number of attempts including the initial try.
  final int maxAttempts;

  /// Base delay before the first retry.
  final Duration baseDelay;

  /// Upper bound for delay between attempts.
  final Duration maxDelay;

  /// If true, doubles the delay for each subsequent attempt.
  final bool exponentialBackoff;

  /// If true, adds a small random jitter to avoid thundering herd.
  final bool jitter;

  /// HTTP status codes that should be retried.
  final Set<int> retryOnStatusCodes;

  /// Dio error types that should be retried.
  final Set<DioExceptionType> retryOnErrorTypes;

  /// HTTP methods allowed to be retried. Defaults to idempotent methods.
  final Set<String> retryMethods;

  /// Use Retry-After header if present for delay calculation.
  final bool respectRetryAfterHeader;

  /// Determine whether a retry should be attempted for the given attempt,
  /// method, response, or error.
  bool shouldAttemptRetry({
    required int attempt,
    required String method,
    Response<dynamic>? response,
    DioException? error,
  }) {
    if (maxAttempts <= 1) {
      return false;
    }
    if (attempt >= maxAttempts) {
      return false;
    }
    if (!retryMethods.contains(method.toUpperCase())) {
      return false;
    }

    if (response != null) {
      return retryOnStatusCodes.contains(response.statusCode);
    }

    if (error != null) {
      return retryOnErrorTypes.contains(error.type);
    }

    return false;
  }

  /// Compute delay for the next attempt, respecting Retry-After if enabled.
  Duration computeDelay(int attempt, {Response<dynamic>? response}) {
    // Respect Retry-After header if present and valid
    if (respectRetryAfterHeader && response != null) {
      final retryAfter = response.headers.value('retry-after');
      if (retryAfter != null) {
        final seconds = int.tryParse(retryAfter);
        if (seconds != null) {
          return Duration(seconds: seconds);
        }
      }
    }

    var delay = baseDelay;
    if (exponentialBackoff && attempt > 1) {
      delay = Duration(
          milliseconds: baseDelay.inMilliseconds * pow(2, attempt - 1).toInt());
    }
    if (delay > maxDelay) {
      delay = maxDelay;
    }
    if (jitter) {
      final r = Random();
      final jitterMs = r.nextInt(delay.inMilliseconds ~/ 4 + 1); // up to 25%
      delay = Duration(milliseconds: delay.inMilliseconds + jitterMs);
    }
    return delay;
  }
}
