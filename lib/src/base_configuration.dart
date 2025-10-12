import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';

import 'auth_refresh_interceptor.dart';
import 'cache.dart';
import 'circuit_breaker.dart';
import 'constants.dart';
import 'rate_limit.dart';
import 'retry_options.dart';

@immutable
class BaseConfiguration {
  const BaseConfiguration({
    required this.baseUrl,
    this.path,
    this.connectTimeout = MAX_CONNECT_TIMEOUT,
    this.receiveTimeout = MAX_RECEIVE_TIMEOUT,
    this.sendTimeout = MAX_SEND_TIMEOUT,
    this.defaultHeaders,
    this.defaultQueryParameters,
    this.extra,
    this.debugMode = false,
    this.allowConcurrency = true,
    this.followRedirects = true,
    this.maxRedirects = MAX_REDIRECTS,
    this.retryOptions = const RetryOptions(),
    this.cachePolicy = const CachePolicy(),
    this.deduplicateRequests = true,
    this.cacheStore,
    this.onRequest,
    this.onResponse,
    this.onError,
    this.rateLimits,
    this.circuitBreakerConfig,
    this.healthProbe,
    this.authRefresh,
    this.onCircuitEvent,
  });

  factory BaseConfiguration.defaultConfig() {
    return const BaseConfiguration(baseUrl: '');
  }

  final String baseUrl;
  final String? path;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;
  final bool debugMode;
  final Map<String, dynamic>? defaultHeaders;
  final Map<String, dynamic>? defaultQueryParameters;
  final Map<String, dynamic>? extra;
  final bool followRedirects;
  final bool allowConcurrency;
  final int maxRedirects;
  final RetryOptions retryOptions;
  final CachePolicy cachePolicy;
  final bool deduplicateRequests;
  final CacheStore? cacheStore;
  final void Function(RequestOptions options)? onRequest;
  final void Function(Response response)? onResponse;
  final void Function(DioException error)? onError;
  final Map<String, RateLimitConfig>? rateLimits; // host -> config
  final CircuitBreakerConfig? circuitBreakerConfig; // global defaults
  // Optional health probe per host or per instance
  final Future<bool> Function(String host)? healthProbe;
  final SimpleAuthRefreshConfig? authRefresh;
  final void Function(String host, CircuitState state)? onCircuitEvent;

  String get _baseUrl => join(baseUrl, path);

  BaseOptions toDioBaseOptions() {
    return BaseOptions(
      baseUrl: _baseUrl,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      headers: defaultHeaders,
      queryParameters: defaultQueryParameters,
      extra: extra,
    );
  }

  BaseConfiguration copyWith({
    String? baseUrl,
    String? path,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Map<String, dynamic>? defaultHeaders,
    Map<String, dynamic>? defaultQueryParameters,
    Map<String, dynamic>? extra,
    bool? followRedirects,
    int? maxRedirects,
    RetryOptions? retryOptions,
    CachePolicy? cachePolicy,
    bool? deduplicateRequests,
    CacheStore? cacheStore,
    void Function(RequestOptions options)? onRequest,
    void Function(Response response)? onResponse,
    void Function(DioException error)? onError,
    Map<String, RateLimitConfig>? rateLimits,
    CircuitBreakerConfig? circuitBreakerConfig,
    Future<bool> Function(String host)? healthProbe,
    SimpleAuthRefreshConfig? authRefresh,
    void Function(String host, CircuitState state)? onCircuitEvent,
  }) {
    return BaseConfiguration(
      baseUrl: baseUrl ?? this.baseUrl,
      path: path ?? this.path,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      defaultQueryParameters:
          defaultQueryParameters ?? this.defaultQueryParameters,
      extra: extra ?? this.extra,
      followRedirects: followRedirects ?? this.followRedirects,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      retryOptions: retryOptions ?? this.retryOptions,
      cachePolicy: cachePolicy ?? this.cachePolicy,
      deduplicateRequests: deduplicateRequests ?? this.deduplicateRequests,
      cacheStore: cacheStore ?? this.cacheStore,
      onRequest: onRequest ?? this.onRequest,
      onResponse: onResponse ?? this.onResponse,
      onError: onError ?? this.onError,
      rateLimits: rateLimits ?? this.rateLimits,
      circuitBreakerConfig: circuitBreakerConfig ?? this.circuitBreakerConfig,
      healthProbe: healthProbe ?? this.healthProbe,
      authRefresh: authRefresh ?? this.authRefresh,
      onCircuitEvent: onCircuitEvent ?? this.onCircuitEvent,
    );
  }

  @override
  bool operator ==(covariant BaseConfiguration other) {
    if (identical(this, other)) {
      return true;
    }

    final mapEquals = const DeepCollectionEquality().equals;

    return other.baseUrl == baseUrl &&
        other.path == path &&
        other.connectTimeout == connectTimeout &&
        other.receiveTimeout == receiveTimeout &&
        other.sendTimeout == sendTimeout &&
        other.debugMode == debugMode &&
        mapEquals(other.defaultHeaders, defaultHeaders) &&
        mapEquals(other.defaultQueryParameters, defaultQueryParameters) &&
        mapEquals(other.extra, extra) &&
        other.followRedirects == followRedirects &&
        other.maxRedirects == maxRedirects &&
        other.retryOptions == retryOptions &&
        other.cachePolicy == cachePolicy &&
        other.deduplicateRequests == deduplicateRequests &&
        other.cacheStore == cacheStore &&
        other.onRequest == onRequest &&
        other.onResponse == onResponse &&
        other.onError == onError &&
        other.rateLimits == rateLimits &&
        other.circuitBreakerConfig == circuitBreakerConfig &&
        other.healthProbe == healthProbe &&
        other.authRefresh == authRefresh &&
        other.onCircuitEvent == onCircuitEvent;
  }

  @override
  int get hashCode {
    return baseUrl.hashCode ^
        path.hashCode ^
        connectTimeout.hashCode ^
        receiveTimeout.hashCode ^
        sendTimeout.hashCode ^
        debugMode.hashCode ^
        defaultHeaders.hashCode ^
        defaultQueryParameters.hashCode ^
        extra.hashCode ^
        followRedirects.hashCode ^
        maxRedirects.hashCode ^
        retryOptions.hashCode ^
        cachePolicy.hashCode ^
        deduplicateRequests.hashCode ^
        cacheStore.hashCode ^
        onRequest.hashCode ^
        onResponse.hashCode ^
        onError.hashCode ^
        rateLimits.hashCode ^
        circuitBreakerConfig.hashCode ^
        healthProbe.hashCode ^
        authRefresh.hashCode ^
        onCircuitEvent.hashCode;
  }
}
