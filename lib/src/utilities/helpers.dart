Type typeOf<T>() => T;

Future<T?> asyncTryCatchDelegate<T>({
  required Future<T> Function() tryBlock,
  T Function()? fac,
  void Function(dynamic error, StackTrace stackTrace)? exceptionCallback,
}) async {
  try {
    return await tryBlock();
  } catch (e, stackTrace) {
    if (exceptionCallback != null) {
      exceptionCallback(e, stackTrace);
    }

    return fac != null ? fac() : null;
  }
}
