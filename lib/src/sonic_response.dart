// ignore_for_file: public_member_api_docs, sort_constructors_first
part of 'sonic_base.dart';

@immutable
class SonicResponse<T> {
  const SonicResponse._({
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

  /// Specifies if the response contains an error.
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

  @override
  bool operator ==(covariant SonicResponse<T> other) {
    if (identical(this, other)) {
      return true;
    }

    final mapEquals = const DeepCollectionEquality().equals;

    return mapEquals(other.extra, extra) &&
        mapEquals(other.headers, headers) &&
        other.data == data &&
        other.statusCode == statusCode &&
        other.message == message &&
        other.sonicError == sonicError;
  }

  @override
  int get hashCode {
    return extra.hashCode ^
        headers.hashCode ^
        data.hashCode ^
        statusCode.hashCode ^
        message.hashCode ^
        sonicError.hashCode;
  }
}
