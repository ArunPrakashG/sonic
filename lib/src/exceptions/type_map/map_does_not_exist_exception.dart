import '../../sonic_error.dart';

class MapDoesNotExistException extends SonicError {
  const MapDoesNotExistException(
      {required String message, required StackTrace stackTrace})
      : super(message: message, stackTrace: stackTrace);
}
