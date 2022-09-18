// ignore_for_file: public_member_api_docs, sort_constructors_first
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes, avoid_returning_this

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart' as sync;

import 'base_configuration.dart';
import 'enums.dart';
import 'exceptions/client_not_initialized_exception.dart';
import 'exceptions/decoder_not_exists_exception.dart';
import 'sonic_error.dart';
import 'sonic_progress.dart';
import 'typedefs.dart';
import 'utilities/helpers.dart';
import 'utilities/type_map.dart';

part 'sonic_response.dart';

/// A Network Client with a Fluent API and improved type system for responses.
class Sonic {
  /// Default Constructor.
  ///
  /// [BaseConfiguration] is used to configure this instance of [Sonic]
  ///
  /// [instanceTag] is used to identify an instance of [Sonic]
  Sonic({
    required this.baseConfiguration,
    this.instanceTag,
  });

  /// Named Consturctor which calls [initialize] method as well.
  ///
  /// [BaseConfiguration] is used to configure this instance of [Sonic]
  ///
  /// [instanceTag] is used to identify an instance of [Sonic]
  Sonic.initialize({
    required this.baseConfiguration,
    this.instanceTag,
  }) {
    initialize();
  }

  /// The Base Configuration.
  ///
  /// **Read Only**
  final BaseConfiguration baseConfiguration;

  /// The Instance Tag which is used to identify this instance.
  ///
  /// **Read Only**
  final String? instanceTag;
  TypeMap? _instanceTypeMap;
  Dio? _dioClient;
  bool _initialized = false;
  sync.Lock? _lock;

  /// Specifys if the client is ready for network calls.
  ///
  /// Will be true if the client has finished initialization.
  bool get isReady => _initialized;

  TypeMap get _typeMap {
    if (_instanceTypeMap == null) {
      throw ClientNotInitializedException(
        message:
            'Sonic Client is not yet initialized. Did you forget to call initialize()?',
        stackTrace: StackTrace.current,
      );
    }

    return _instanceTypeMap!;
  }

  Dio get _client {
    if (_dioClient == null) {
      throw ClientNotInitializedException(
        message:
            'Sonic Client is not yet initialized. Did you forget to call initialize()?',
        stackTrace: StackTrace.current,
      );
    }

    return _dioClient!;
  }

  /// Initializes the [Sonic] Client with base configuration.
  ///
  /// This method must be called if you are using the default constructor. If not, [ClientNotInitializedException] exception will be thrown.
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

    if (!baseConfiguration.allowConcurrency) {
      _lock = sync.Lock();
    }

    _initialized = true;
  }

  /// Registers a type with the client.
  ///
  /// This is used to register a decoder for a response model class.
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

  /// Creates a new Request Builder.
  ///
  /// Request Builders are used to build the request. Once build, calling `execute()` on them will execute the request and provide the response.
  SonicRequestBuilder<T> create<T>({
    required String url,
    HttpMethod method = HttpMethod.get,
    bool rawRequest = false,
  }) {
    if (rawRequest) {
      return SonicRequestBuilder<T>._(
        this,
        url,
        method,
        null,
        rawRequest,
      );
    }

    final decoder = _typeMap.getDecoderForType<T>(false);

    return SonicRequestBuilder<T>._(
      this,
      url,
      method,
      decoder,
      rawRequest,
    );
  }

  Future<SonicResponse<T>> _runRequest<T>(
    SonicRequestBuilder<T> requestBuilder, [
    bool rawRequest = false,
  ]) async {
    Response<dynamic> response;

    final requestFuture = _client.request<dynamic>(
      requestBuilder._url,
      data: requestBuilder._body,
      cancelToken: requestBuilder._cancelToken,
      queryParameters: requestBuilder._queryParameters,
      onSendProgress: (count, total) {
        if (requestBuilder._sentProgress != null) {
          requestBuilder._sentProgress!(
            SonicProgress(current: count, total: total),
          );
        }
      },
      onReceiveProgress: (count, total) {
        if (requestBuilder._receiveProgress != null) {
          requestBuilder._receiveProgress!(
            SonicProgress(current: count, total: total),
          );
        }
      },
      options: Options(
        method: requestBuilder._method.name,
        extra: requestBuilder._extra,
        headers: requestBuilder._headers,
        maxRedirects: requestBuilder._maxRedirects,
        followRedirects: requestBuilder._followRedirects,
        sendTimeout: requestBuilder._sentTimeout,
        receiveTimeout: requestBuilder._receiveTimeout,
      ),
    );

    if (!baseConfiguration.allowConcurrency && _lock != null) {
      response = await _lock!.synchronized(
        () async => requestFuture,
      );
    } else {
      response = await requestFuture;
    }

    final decoder = requestBuilder._decoder;

    if (decoder == null && !rawRequest) {
      throw DecoderDoesNotExistException(
        message:
            'Decoder for type ${typeOf<T>()} is not provided. Did you forgot to register a decoder?',
        stackTrace: StackTrace.current,
      );
    }

    if (!rawRequest) {
      final cachedDecoder = _typeMap.getDecoderForType<T>(false);

      if (cachedDecoder == null && decoder != null) {
        _typeMap.addDecoderForType<T>(decoder);
      }
    }

    return SonicResponse<T>._(
      statusCode: response.statusCode ?? -1,
      message: response.statusMessage,
      data: rawRequest ? response.data as T : decoder!(response.data),
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

/// The Request Builder.
///
/// The Type [T] is the response model type.
class SonicRequestBuilder<T> {
  SonicRequestBuilder._(
    this._sonic,
    this._url,
    this._method,
    this._decoder,
    this._rawRequest,
  );

  final Sonic _sonic;
  final String _url;

  bool _rawRequest;
  HttpMethod _method;
  Map<String, dynamic>? _headers;
  Map<String, dynamic>? _extra;
  dynamic _body;
  Map<String, dynamic>? _queryParameters;
  T Function(dynamic json)? _decoder;
  CancelToken? _cancelToken;
  bool? _followRedirects;
  int? _maxRedirects;
  int? _receiveTimeout;
  int? _sentTimeout;
  SonicProgressCallback? _sentProgress;
  SonicProgressCallback? _receiveProgress;
  void Function(SonicError error)? _onError;
  void Function()? _onRunning;
  void Function(SonicResponse<T> data)? _onSuccess;

  /// Adds a response decoder which decodes the response to the specified type.
  ///
  /// **NOTES**</br>
  /// - If you have already used the same model with another request, the decoder will be cached and therefore, you don't need to pass it again.
  /// - If you have used the `registerType()` method, you don't need to pass a decoder here either.
  SonicRequestBuilder<T> withDecoder(T Function(dynamic json) decoder) {
    _decoder = decoder;
    return this;
  }

  /// Register a callback to receive progress for senting (uploading)
  SonicRequestBuilder<T> withSentProgress(
    SonicProgressCallback sendProgress,
  ) {
    _sentProgress = sendProgress;
    return this;
  }

  /// Register a callback to receive progress for receiving (downloading)
  SonicRequestBuilder<T> withReceiveProgress(
    SonicProgressCallback receiveProgress,
  ) {
    _receiveProgress = receiveProgress;
    return this;
  }

  /// Specifies a receive timeout for this request.
  SonicRequestBuilder<T> withReceiveTimeout(int timeout) {
    _receiveTimeout = timeout;
    return this;
  }

  /// Specifies a sent timeout for this request.
  SonicRequestBuilder<T> withSendTimeout(int timeout) {
    _sentTimeout = timeout;
    return this;
  }

  /// Specifies if we should follow redirects while making the request.
  SonicRequestBuilder<T> followRedirects() {
    _followRedirects = true;
    return this;
  }

  /// Specifies the maximum redirect count we should follow.
  SonicRequestBuilder<T> maxRedirects(int maxRedirects) {
    _maxRedirects = maxRedirects;
    return this;
  }

  /// Specifies the request to be a `POST` Request.
  SonicRequestBuilder<T> post() {
    _method = HttpMethod.post;
    return this;
  }

  /// Specifies the request to be a `GET` Request.
  SonicRequestBuilder<T> get() {
    _method = HttpMethod.get;
    return this;
  }

  /// Specifies the request to be a `PATCH` Request.
  SonicRequestBuilder<T> patch() {
    _method = HttpMethod.patch;
    return this;
  }

  /// Specifies the request to be a `DELETE` Request.
  SonicRequestBuilder<T> delete() {
    _method = HttpMethod.delete;
    return this;
  }

  /// Specifies the request to be a `PUT` Request.
  SonicRequestBuilder<T> put() {
    _method = HttpMethod.put;
    return this;
  }

  /// Adds body to the request.
  SonicRequestBuilder<T> withBody(dynamic body) {
    _body = body;
    return this;
  }

  /// Marks the request as a Raw Request. (No Response Type Parsing)
  SonicRequestBuilder<T> asRawRequest() {
    _rawRequest = true;
    return this;
  }

  /// Can be used to pass extra data to the request. The data will be available on the response. This is a feature from [Dio].
  SonicRequestBuilder<T> withExtra(Map<String, dynamic> extra) {
    _extra = extra;
    return this;
  }

  /// Adds a cancel token to the request by which, the request can be cancelled.
  SonicRequestBuilder<T> withCancelToken(CancelToken cancelToken) {
    _cancelToken = cancelToken;
    return this;
  }

  /// Used to add a pair of Query Parameters to the request.
  SonicRequestBuilder<T> withQueryParameter(String key, dynamic value) {
    _queryParameters ??= <String, dynamic>{};
    _queryParameters![key] = value;
    return this;
  }

  /// Used to add Query Parameters to the request.
  SonicRequestBuilder<T> withQueryParameters(Map<String, dynamic> parameters) {
    _queryParameters ??= <String, dynamic>{};
    _queryParameters!.addAll(parameters);
    return this;
  }

  /// Used to add a pair of Header to the request.
  SonicRequestBuilder<T> withHeader(String key, dynamic value) {
    _headers ??= <String, dynamic>{};
    _headers![key] = value;
    return this;
  }

  /// Used to add Headers to the request.
  SonicRequestBuilder<T> withHeaders(Map<String, dynamic> headers) {
    _headers ??= <String, dynamic>{};
    _headers!.addAll(headers);
    return this;
  }

  /// Callback triggered when the data is received and the status code indicates success.
  SonicRequestBuilder<T> onSuccess(
    void Function(SonicResponse<T> data) callback,
  ) {
    _onSuccess = callback;
    return this;
  }

  /// Callback triggered when there is an error with the requesting process.
  ///
  /// Errors are defined as [SonicError] object which contain `message` and `stackTrace`
  SonicRequestBuilder<T> onError(void Function(SonicError error) callback) {
    _onError = callback;
    return this;
  }

  /// Callback triggered when the request is in progress.
  SonicRequestBuilder<T> onLoading(void Function() callback) {
    _onRunning = callback;
    return this;
  }

  /// Called to execute the request with the parameters.
  ///
  /// The result `Future` contains [SonicResponse] which contains the response instance and meta data on the request.
  Future<SonicResponse<T>> execute() async {
    SonicError? errorObject;

    if (_onRunning != null) {
      _onRunning!();
    }

    final response = await task<SonicResponse<T>>(
      callback: () async => _sonic._runRequest<T>(this, _rawRequest),
      fallback: () {
        return SonicResponse._(
          statusCode: -1,
          sonicError: errorObject,
        );
      },
      onException: (dynamic error, stackTrace) {
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

  @override
  bool operator ==(covariant SonicRequestBuilder<T> other) {
    if (identical(this, other)) {
      return true;
    }

    final mapEquals = const DeepCollectionEquality().equals;

    return other._sonic == _sonic &&
        other._url == _url &&
        other._rawRequest == _rawRequest &&
        other._method == _method &&
        mapEquals(other._headers, _headers) &&
        mapEquals(other._extra, _extra) &&
        other._body == _body &&
        mapEquals(other._queryParameters, _queryParameters) &&
        other._decoder == _decoder &&
        other._cancelToken == _cancelToken &&
        other._onError == _onError &&
        other._onRunning == _onRunning &&
        other._onSuccess == _onSuccess;
  }

  @override
  int get hashCode {
    return _sonic.hashCode ^
        _url.hashCode ^
        _rawRequest.hashCode ^
        _method.hashCode ^
        _headers.hashCode ^
        _extra.hashCode ^
        _body.hashCode ^
        _queryParameters.hashCode ^
        _decoder.hashCode ^
        _cancelToken.hashCode ^
        _onError.hashCode ^
        _onRunning.hashCode ^
        _onSuccess.hashCode;
  }
}
