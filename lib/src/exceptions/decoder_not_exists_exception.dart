import '../sonic_error.dart';

class DecoderDoesNotExistException extends SonicError {
  const DecoderDoesNotExistException(
      {required String message, required StackTrace stackTrace})
      : super(message: message, stackTrace: stackTrace);
}
