class CircuitOpenException implements Exception {
  CircuitOpenException(this.message);
  final String message;
  @override
  String toString() => 'CircuitOpenException: $message';
}
