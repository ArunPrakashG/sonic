import 'dart:async';

enum CircuitState { closed, open, halfOpen }

class CircuitBreakerConfig {
  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.coolDown = const Duration(seconds: 30),
    this.halfOpenTrial = 1,
  });

  final int failureThreshold;
  final Duration coolDown;
  final int halfOpenTrial;
}

typedef CircuitEventHandler = void Function(String key, CircuitState state);

class CircuitBreaker {
  CircuitBreaker(this.config, {this.onEvent});

  final CircuitBreakerConfig config;
  final CircuitEventHandler? onEvent;

  final _stateByKey = <String, CircuitState>{};
  final _failures = <String, int>{};
  final _openedAt = <String, DateTime>{};
  final _trials = <String, int>{};

  CircuitState stateFor(String key) => _stateByKey[key] ?? CircuitState.closed;

  bool allowRequest(String key) {
    final state = stateFor(key);
    if (state == CircuitState.closed) {
      return true;
    }
    if (state == CircuitState.open) {
      final openedAt = _openedAt[key];
      if (openedAt == null) {
        return false;
      }
      if (DateTime.now().difference(openedAt) >= config.coolDown) {
        _transition(key, CircuitState.halfOpen);
        _trials[key] = 0;
        return true; // allow trial
      }
      return false;
    }
    // half-open: allow limited trials
    final t = _trials[key] ?? 0;
    if (t < config.halfOpenTrial) {
      _trials[key] = t + 1;
      return true;
    }
    return false;
  }

  void recordSuccess(String key) {
    final state = stateFor(key);
    if (state == CircuitState.halfOpen || state == CircuitState.open) {
      _reset(key);
      _transition(key, CircuitState.closed);
    } else {
      _failures[key] = 0;
    }
  }

  void recordFailure(String key) {
    final state = stateFor(key);
    final count = (_failures[key] ?? 0) + 1;
    _failures[key] = count;
    if (state == CircuitState.halfOpen) {
      _open(key);
      return;
    }
    if (count >= config.failureThreshold) {
      _open(key);
    }
  }

  void _open(String key) {
    _openedAt[key] = DateTime.now();
    _transition(key, CircuitState.open);
  }

  void _reset(String key) {
    _failures[key] = 0;
    _openedAt.remove(key);
    _trials.remove(key);
  }

  void _transition(String key, CircuitState next) {
    _stateByKey[key] = next;
    onEvent?.call(key, next);
  }

  /// If circuit is open, run a health probe. If probe returns true, move to half-open.
  Future<void> probeAndMaybeHalfOpen(
      String key, Future<bool> Function(String host) probe) async {
    if (stateFor(key) != CircuitState.open) {
      return;
    }
    final ok = await probe(key);
    if (ok) {
      _transition(key, CircuitState.halfOpen);
      _trials[key] = 0;
    }
  }
}
