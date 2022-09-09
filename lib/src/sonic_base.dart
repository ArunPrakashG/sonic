// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes, avoid_returning_this

import 'package:dio/dio.dart';

import 'base_configuration.dart';
import 'enums.dart';
import 'exceptions/client_not_initialized_exception.dart';

import 'exceptions/decoder_not_exists_exception.dart';
import 'sonic_error.dart';
import 'utilities/helpers.dart';
import 'utilities/type_map.dart';

part 'sonic_response.dart';

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
      throw ClientNotInitializedException(
        message:
            'Sonic Client is not yet initialized. Did you forget to call initialize()?',
        stackTrace: StackTrace.current,
      );
    }

    return _instanceTypeMap!;
  }

  Dio get _client {
    if (_dioClient == null || !_initialized) {
      throw ClientNotInitializedException(
        message:
            'Sonic Client is not yet initialized. Did you forget to call initialize()?',
        stackTrace: StackTrace.current,
      );
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

  void registerType<T>({
    required T Function(dynamic json) decoder,
    Map<String, dynamic> Function(T instance)? encoder,
  }) {
    _typeMap.addDecoderForType<T>(decoder);

    if (encoder != null) {
      final casted = encoder as Map<String, dynamic> Function(dynamic);
      _typeMap.addEncoderForType<T>(casted);
    }
  }

  SonicRequest<T> create<T>({
    required String url,
    HttpMethod method = HttpMethod.get,
  }) {
    final decoder = _typeMap.getDecoderForType<T>(false);

    return SonicRequest<T>._(
      this,
      url,
      method,
      decoder,
    );
  }

  Future<SonicResponse<T>> _runRequest<T>(
    SonicRequest<T> request,
  ) async {
    final response = await _client.request<dynamic>(
      request._url,
      data: request._body,
      cancelToken: request._cancelToken,
      queryParameters: request._queryParameters,
      options: Options(
        method: request._method.name,
        extra: request._extra,
        headers: request._headers,
      ),
    );

    final decoder = request._decoder;

    if (decoder == null) {
      throw DecoderDoesNotExistException(
        message:
            'Decoder for type ${typeOf<T>()} is not provided. Did you forgot to register a decoder?',
        stackTrace: StackTrace.current,
      );
    }

    final cachedDecoder = _typeMap.getDecoderForType<T>(false);

    if (cachedDecoder == null) {
      _typeMap.addDecoderForType<T>(decoder);
    }

    return SonicResponse<T>._(
      statusCode: response.statusCode ?? -1,
      message: response.statusMessage,
      data: decoder(response.data),
      headers: response.headers.map,
    );
  }

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

  HttpMethod _method;
  Map<String, dynamic>? _headers;
  Map<String, dynamic>? _extra;
  dynamic _body;
  Map<String, dynamic>? _queryParameters;
  T Function(dynamic json)? _decoder;
  CancelToken? _cancelToken;
  void Function(SonicError error)? _onError;
  void Function()? _onRunning;
  void Function(SonicResponse<T> data)? _onSuccess;

  SonicRequest<T> withDecoder(T Function(dynamic json) decoder) {
    _decoder = decoder;
    return this;
  }

  SonicRequest<T> post() {
    _method = HttpMethod.post;
    return this;
  }

  SonicRequest<T> get() {
    _method = HttpMethod.get;
    return this;
  }

  SonicRequest<T> patch() {
    _method = HttpMethod.patch;
    return this;
  }

  SonicRequest<T> delete() {
    _method = HttpMethod.delete;
    return this;
  }

  SonicRequest<T> put() {
    _method = HttpMethod.put;
    return this;
  }

  SonicRequest<T> withBody(dynamic body) {
    _body = body;
    return this;
  }

  SonicRequest<T> withExtra(Map<String, dynamic> extra) {
    _extra = extra;
    return this;
  }

  SonicRequest<T> withCancelToken(CancelToken cancelToken) {
    _cancelToken = cancelToken;
    return this;
  }

  SonicRequest<T> withQueryParameter(String key, dynamic value) {
    _queryParameters ??= <String, dynamic>{};
    _queryParameters![key] = value;
    return this;
  }

  SonicRequest<T> withQueryParameters(Map<String, dynamic> parameters) {
    _queryParameters ??= <String, dynamic>{};
    _queryParameters!.addAll(parameters);
    return this;
  }

  SonicRequest<T> withHeader(String key, dynamic value) {
    _headers ??= <String, dynamic>{};
    _headers![key] = value;
    return this;
  }

  SonicRequest<T> withHeaders(Map<String, dynamic> headers) {
    _headers ??= <String, dynamic>{};
    _headers!.addAll(headers);
    return this;
  }

  SonicRequest<T> onSuccess(void Function(SonicResponse<T> data) callback) {
    _onSuccess = callback;
    return this;
  }

  SonicRequest<T> onError(void Function(SonicError error) callback) {
    _onError = callback;
    return this;
  }

  SonicRequest<T> onLoading(void Function() callback) {
    _onRunning = callback;
    return this;
  }

  Future<SonicResponse<T>> execute() async {
    SonicError? errorObject;

    if (_onRunning != null) {
      _onRunning!();
    }

    final response = await asyncTryCatchDelegate<SonicResponse<T>>(
      tryBlock: () async => _sonic._runRequest<T>(this),
      fac: () {
        return SonicResponse._(
          statusCode: -1,
          sonicError: errorObject,
        );
      },
      exceptionCallback: (dynamic error, stackTrace) {
        if (error is DioError) {
          errorObject = SonicError(
            message: error.message,
            stackTrace: stackTrace,
          );

          return;
        }

        if (error is SonicError) {
          errorObject = error;
          return;
        }

        errorObject = SonicError(
          message: error.toString(),
          stackTrace: stackTrace,
        );
      },
    );

    if (errorObject != null && _onError != null) {
      _onError!(errorObject!);
    }

    if (response == null) {
      return SonicResponse<T>._(
        statusCode: -1,
        sonicError: errorObject ??
            SonicError(
              message: 'Request failed due to unknown reasons.',
              stackTrace: StackTrace.current,
            ),
      );
    }

    if (!response.isSuccess) {
      return response;
    }

    if (_onSuccess != null) {
      _onSuccess!(response);
    }

    return response;
  }
}
