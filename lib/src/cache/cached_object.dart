import '../utilities/helpers.dart';

class CachedObject<T> {
  const CachedObject({
    required this.key,
    required this.data,
    required this.expiry,
  });

  final String key;
  final Map<String, dynamic> data;
  final DateTime? expiry;

  bool get isExpired {
    if (expiry == null) {
      // no expiry
      return false;
    }

    final difference = DateTime.now().difference(expiry!);

    return difference.inMilliseconds > 0;
  }

  Type get typeKey => typeOf<T>();
}
