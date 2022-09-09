import '../exceptions/type_map/map_does_not_exist_exception.dart';
import 'helpers.dart';

class TypeMap {
  final Map<Type, dynamic Function(dynamic instance)> _decoders = {};
  final Map<Type, Map<String, dynamic> Function(dynamic instance)> _encoders =
      {};

  void addDecoderForType<T>(T Function(dynamic instance) decoder) {
    _decoders[typeOf<T>()] = decoder;
  }

  void removeDecoderForType<T>() {
    _decoders.remove(typeOf<T>());
  }

  T Function(dynamic instance)? getDecoderForType<T>([
    // ignore: avoid_positional_boolean_parameters
    bool throwOnNull = true,
  ]) {
    if (_decoders[typeOf<T>()] == null) {
      if (!throwOnNull) {
        return null;
      }

      throw MapDoesNotExistException(
        message: 'Map of type: ${typeOf<T>()} does not exist!',
        stackTrace: StackTrace.current,
      );
    }

    return _decoders[typeOf<T>()] as T Function(dynamic instance);
  }

  void addEncoderForType<T>(
      Map<String, dynamic> Function(dynamic instance) encoder) {
    _encoders[typeOf<T>()] = encoder;
  }

  void removeEncoderForType<T>() {
    _encoders.remove(typeOf<T>());
  }

  Map<String, dynamic> Function(T? instance) getEncoderForType<T>() {
    if (_encoders[typeOf<T>()] == null) {
      throw MapDoesNotExistException(
        message: 'Map of type: ${typeOf<T>()} does not exist!',
        stackTrace: StackTrace.current,
      );
    }

    return _encoders[typeOf<T>()] as Map<String, dynamic> Function(T? instance);
  }

  void addJsonPairForType<T>({
    required Map<String, dynamic> Function(dynamic instance) encoder,
    required T Function(dynamic instance) decoder,
  }) {
    addDecoderForType<T>(decoder);
    addEncoderForType<T>(encoder);
  }
}
