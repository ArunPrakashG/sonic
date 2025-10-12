import 'dart:async';

import 'package:sonic/src/circuit_breaker.dart';
import 'package:test/test.dart';

void main() {
  group('CircuitBreaker state transitions', () {
    test(
        'Closed -> Open after threshold; Open blocks; HalfOpen trials; success closes',
        () async {
      final cb = CircuitBreaker(
        const CircuitBreakerConfig(
          failureThreshold: 3,
          coolDown: Duration(milliseconds: 50),
        ),
      );

      const host = 'api.example.com';

      // Initially closed
      expect(cb.stateFor(host), CircuitState.closed);
      expect(cb.allowRequest(host), isTrue);

      // Record failures fewer than threshold keeps closed
      cb.recordFailure(host); // 1
      expect(cb.stateFor(host), CircuitState.closed);
      cb.recordFailure(host); // 2
      expect(cb.stateFor(host), CircuitState.closed);

      // Next failure reaches threshold -> open
      cb.recordFailure(host); // 3
      expect(cb.stateFor(host), CircuitState.open);

      // While open and before cooldown, should not allow
      expect(cb.allowRequest(host), isFalse);

      // Wait for cooldown, now allow a half-open trial
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
          cb.allowRequest(host), isTrue); // transitions to half-open internally
      expect(
          cb.stateFor(host), anyOf(CircuitState.halfOpen, CircuitState.open));

      // A failure during half-open re-opens circuit
      cb.recordFailure(host);
      expect(cb.stateFor(host), CircuitState.open);

      // After cooldown again, a trial followed by success closes the circuit
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(cb.allowRequest(host), isTrue); // half-open trial
      cb.recordSuccess(host);
      expect(cb.stateFor(host), CircuitState.closed);

      // In closed, subsequent successes keep it closed
      cb.recordSuccess(host);
      expect(cb.stateFor(host), CircuitState.closed);
    });
  });
}
