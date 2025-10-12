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
/// Global defaults for the Sonic client instance.
///
/// These values map to Dio's [BaseOptions] and additional Sonic features like
/// caching, retries, rate limiting, circuit breaking, and token refresh.
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

  /// A minimal configuration with an empty baseUrl.
  factory BaseConfiguration.defaultConfig() {
    return const BaseConfiguration(baseUrl: '');
  }
  /// Base URL for requests. You can also supply a [path] which will be joined.
  final String baseUrl;
  /// Optional path joined to [baseUrl].
  final String? path;
  /// Connect timeout for new connections.
  final Duration connectTimeout;
  /// Receive timeout for responses.
  final Duration receiveTimeout;
  /// Send timeout for request bodies.
  final Duration sendTimeout;
  /// Enable verbose Dio logging interceptor.
  final bool debugMode;
  /// Default headers added to each request.
  final Map<String, dynamic>? defaultHeaders;
  /// Default query parameters added to each request.
  final Map<String, dynamic>? defaultQueryParameters;
  /// Arbitrary extra values attached to Dio options.
  final Map<String, dynamic>? extra;
  /// Whether to follow redirects.
  final bool followRedirects;
  /// Allow concurrent requests or serialize them through a lock.
  final bool allowConcurrency;
  /// Maximum redirect count when [followRedirects] is true.
  final int maxRedirects;
  /// Default retry options for this client.
  final RetryOptions retryOptions;
  /// Default cache policy for GETs.
  final CachePolicy cachePolicy;
  /// Whether to deduplicate identical in-flight GET requests.
  final bool deduplicateRequests;
  /// Optional custom cache store (in-memory by default).
  final CacheStore? cacheStore;
  /// Hook invoked before sending a request.
  final void Function(RequestOptions options)? onRequest;
  /// Hook invoked after receiving a response (success or 304).
  final void Function(Response response)? onResponse;
  /// Hook invoked when an error bubbles up.
  final void Function(DioException error)? onError;
  /// Per-host rate limit configuration. Key is host (example.com).
  final Map<String, RateLimitConfig>? rateLimits; // host -> config
  /// Circuit breaker configuration applied per-host.
  final CircuitBreakerConfig? circuitBreakerConfig; // global defaults
  // Optional health probe per host or per instance
  final Future<bool> Function(String host)? healthProbe;
  /// Simple token refresh configuration to deduplicate 401-triggered refresh.
  final SimpleAuthRefreshConfig? authRefresh;
  /// Callback invoked when a circuit state changes.
  final void Function(String host, CircuitState state)? onCircuitEvent;

  String get _baseUrl => join(baseUrl, path);

  /// Convert to Dio [BaseOptions].
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

  /// Create a copy with selective overrides.
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
