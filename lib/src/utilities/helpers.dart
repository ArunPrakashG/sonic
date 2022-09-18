Type typeOf<T>() => T;

Future<T?> task<T>({
  required Future<T> Function() callback,
  T Function()? fallback,
  void Function(dynamic error, StackTrace stackTrace)? onException,
}) async {
  try {
    return await callback();
  } catch (e, stackTrace) {
    if (onException != null) {
      onException(e, stackTrace);
    }

    return fallback != null ? fallback() : null;
  }
}
