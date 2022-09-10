import '../sonic_error.dart';

class ClientNotInitializedException extends SonicError {
  const ClientNotInitializedException(
      {required String message, required StackTrace stackTrace})
      : super(message: message, stackTrace: stackTrace);
}
