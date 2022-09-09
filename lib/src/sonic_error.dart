class SonicError implements Exception {
  const SonicError({
    required this.message,
    required this.stackTrace,
  });

  final String message;
  final StackTrace stackTrace;
}
