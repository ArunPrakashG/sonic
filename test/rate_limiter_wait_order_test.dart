import 'dart:async';

import 'package:sonic/src/enums.dart';
import 'package:sonic/src/rate_limit.dart';
import 'package:test/test.dart';

void main() {
  test('high priority tends to wait less than low priority', () async {
    final limiter = TokenBucketLimiter(const RateLimitConfig(
      permitsPerSecond: 1,
    ));

    // Consume initial token to force waits on next acquires.
    await limiter.acquire();

    // Run multiple pairs to account for timing jitter
    const pairs = 5;
    var highWins = 0;
    for (var i = 0; i < pairs; i++) {
      // Slight stagger so both must wait; high should tend to be less
      Future<int> lowF() async =>
          (await limiter.acquire(priority: RequestPriority.low)).inMilliseconds;
      // give a tiny head start to avoid exact same timestamp
      await Future<void>.delayed(const Duration(milliseconds: 5));
      Future<int> highF() async =>
          (await limiter.acquire(priority: RequestPriority.high))
              .inMilliseconds;

      final lowMs = await lowF();
      final highMs = await highF();
      if (highMs <= lowMs) {
        highWins++;
      }
    }

    // We expect high to win at least most of the time
    expect(highWins, greaterThanOrEqualTo(3));
  });
}
