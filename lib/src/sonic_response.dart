part of 'sonic_base.dart';

class SonicResponse<T> {
  SonicResponse._({
    this.extra,
    this.headers,
    this.data,
    required this.statusCode,
    this.message,
    this.sonicError,
  });

  final Map<String, dynamic>? extra;
  final Map<String, List<String>>? headers;
  final T? data;
  final int statusCode;
  final String? message;
  final SonicError? sonicError;

  bool get isSuccess => statusCode >= 200 && statusCode <= 299;
  bool get hasError => sonicError != null;

  Y to<Y>(Y Function(SonicResponse<T> data) callback) {
    return callback(this);
  }

  Y on<Y>(
    Y Function(T? data) data,
    Y Function(SonicError? error) error,
  ) {
    if (hasError || (!isSuccess && this.data == null)) {
      return error(sonicError);
    }

    return data(this.data);
  }
}
