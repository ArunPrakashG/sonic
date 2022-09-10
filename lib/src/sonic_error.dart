// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:meta/meta.dart';

@immutable
class SonicError implements Exception {
  const SonicError({
    required this.message,
    required this.stackTrace,
  });

  final String message;
  final StackTrace stackTrace;

  @override
  bool operator ==(covariant SonicError other) {
    if (identical(this, other)) {
      return true;
    }

    return other.message == message && other.stackTrace == stackTrace;
  }

  @override
  int get hashCode => message.hashCode ^ stackTrace.hashCode;
}
