import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

void main() {
  test('CircuitBreaker config and export types compile', () {
    const cfg = CircuitBreakerConfig(failureThreshold: 3);
    expect(cfg.failureThreshold, 3);
    // States are available
    expect(CircuitState.closed.index, 0);
  });
}
