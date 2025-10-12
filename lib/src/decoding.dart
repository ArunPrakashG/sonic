import 'package:meta/meta.dart';

@immutable
class DecodeError {
  const DecodeError({required this.path, required this.message});
  final String path;
  final String message;
}

@immutable
class DecodeResult<T> {
  const DecodeResult({this.value, this.errors = const []});
  final T? value;
  final List<DecodeError> errors;
  bool get isOk => errors.isEmpty && value != null;
}

DecodeResult<T> Function(dynamic json) safeDecoder<T>(
    T Function(dynamic json) decoder) {
  return (dynamic json) {
    try {
      final v = decoder(json);
      return DecodeResult<T>(value: v);
    } catch (e) {
      return DecodeResult<T>(
        errors: [DecodeError(path: '', message: e.toString())],
      );
    }
  };
}
