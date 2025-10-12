import 'dart:async';

import 'enums.dart';

class RateLimitConfig {
  const RateLimitConfig({required this.permitsPerSecond, this.burst = 1});
  final int permitsPerSecond;
  final int burst;
}

class TokenBucketLimiter {
  TokenBucketLimiter(this.config)
      : _tokens = config.burst.toDouble(),
        _last = DateTime.now();

  final RateLimitConfig config;
  double _tokens;
  DateTime _last;

  Future<Duration> acquire(
      {int cost = 1, RequestPriority priority = RequestPriority.normal}) async {
    final start = DateTime.now();
    while (true) {
      _refill();
      if (_tokens >= cost) {
        _tokens -= cost;
        break;
      }
      final deficit = cost - _tokens;
      final secPerToken = 1 / config.permitsPerSecond;
      var waitMs = (deficit * secPerToken * 1000).ceil();
      if (priority == RequestPriority.low) {
        waitMs = (waitMs * 1.5).ceil();
      }
      if (priority == RequestPriority.high) {
        waitMs = (waitMs * 0.7).ceil();
      }
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
    return DateTime.now().difference(start);
  }

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_last).inMilliseconds / 1000.0;
    final add = elapsed * config.permitsPerSecond;
    if (add > 0) {
      _tokens = (_tokens + add).clamp(0, config.burst.toDouble());
      _last = now;
    }
  }
}
