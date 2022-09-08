// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:dio/dio.dart';

import 'base_configuration.dart';
import 'enums.dart';
import 'exceptions/client_not_initialized_exception.dart';
import 'utilities/type_map.dart';

part 'sonic_request.dart';

class Sonic {
  Sonic({
    required this.baseConfiguration,
    this.instanceTag,
  });

  final BaseConfiguration baseConfiguration;
  final String? instanceTag;
  TypeMap? _instanceTypeMap;
  Dio? _dioClient;
  bool _initialized = false;

  TypeMap get _typeMap {
    if (_instanceTypeMap == null || !_initialized) {
      throw ClientNotInitializedException();
    }

    return _instanceTypeMap!;
  }

  Dio get _client {
    if (_dioClient == null || !_initialized) {
      throw ClientNotInitializedException();
    }

    return _dioClient!;
  }

  void initialize() {
    if (_initialized) {
      return;
    }

    final options = baseConfiguration.toDioBaseOptions();

    _dioClient = Dio(options);
    _instanceTypeMap = TypeMap();

    if (baseConfiguration.debugMode) {
      _client.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
        ),
      );
    }

    _initialized = true;
  }

  void registerType<T extends Object>({
    required T Function(dynamic json) decoder,
    Map<String, dynamic> Function(T instance)? encoder,
  }) {
    _typeMap.addDecoderForType<T>(decoder);

    if (encoder != null) {
      final casted = encoder as Map<String, dynamic> Function(dynamic);
      _typeMap.addEncoderForType<T>(casted);
    }
  }

  SonicRequest<T> newRequest<T extends Object>({
    required String url,
    required HttpMethod method,
  }) {
    final decoder = _typeMap.getDecoderForType<T>(false);

    return SonicRequest<T>._(
      this,
      url,
      method,
      decoder,
    );
  }

  void _execute() {}

  @override
  bool operator ==(covariant Sonic other) {
    if (identical(this, other)) {
      return true;
    }

    return other.baseConfiguration == baseConfiguration &&
        other.instanceTag == instanceTag;
  }

  @override
  int get hashCode => baseConfiguration.hashCode ^ instanceTag.hashCode;
}

class SonicRequest<T> {
  SonicRequest._(
    this._sonic,
    this._url,
    this._method,
    this._decoder,
  );

  final Sonic _sonic;
  final String _url;
  final HttpMethod _method;

  T Function(dynamic json)? _decoder;

  // TODO: Define various properties defining the request here

  // TODO: populate these properties with void returning methods
  void withDecoder(T Function(dynamic json) decoder) {
    _decoder = decoder;
  }

  Future<void> execute() async {
    _sonic._execute();
  }
}
