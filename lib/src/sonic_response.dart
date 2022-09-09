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

  /// Specifies if the request is a success.
  ///
  /// status code >= 200 and status code <= 299
  bool get isSuccess => statusCode >= 200 && statusCode <= 299;

  /// Specifies if the response is an error response.
  bool get hasError => sonicError != null;

  /// Transforms this instance of [SonicResponse] to [Y] type with [callback]
  Y to<Y>(Y Function(SonicResponse<T> data) callback) {
    return callback(this);
  }

  /// An easier syntax than writting if conditions to return instances based on response.
  Y on<Y>(
    Y Function(T? data) onData,
    Y Function(SonicError? error) onError,
  ) {
    if (hasError || (!isSuccess && data == null)) {
      return onError(sonicError);
    }

    return onData(data);
  }
}
