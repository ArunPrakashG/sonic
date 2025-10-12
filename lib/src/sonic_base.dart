// ignore_for_file: public_member_api_docs, sort_constructors_first
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes, avoid_returning_this

import 'dart:async' show unawaited;
import 'dart:io' show HttpDate, Platform;
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart' as sync;

import 'auth_refresh_interceptor.dart';
import 'base_configuration.dart';
import 'cache.dart';
import 'circuit_breaker.dart';
import 'decoding.dart';
import 'enums.dart';
import 'exceptions/circuit_open_exception.dart';
import 'exceptions/client_not_initialized_exception.dart';
import 'exceptions/decoder_not_exists_exception.dart';
import 'pagination.dart';
import 'rate_limit.dart';
import 'retry_options.dart';
import 'sonic_error.dart';
import 'sonic_progress.dart';
import 'typedefs.dart';
import 'utilities/helpers.dart';
import 'utilities/type_map.dart';

part 'sonic_response.dart';

/// A high-level HTTP client with a fluent builder API on top of Dio.
///
/// Sonic focuses on ergonomics and production features:
/// - Typed decoders with a small, cached type map
/// - Retries with backoff/jitter and Retry-After handling
/// - Caching (TTL/LRU, SWR) with ETag/Last-Modified validation
/// - Request deduplication and per-host rate limiting with priority
/// - Circuit breaker with event hooks
/// - Convenient pagination helpers and multipart uploads
///
/// Use [create] to start a [SonicRequestBuilder], configure the request with
/// builder methods, and call [SonicRequestBuilder.execute] to perform it.
class Sonic {
  /// Default Constructor.
  ///
  /// Creates an instance configured by [baseConfiguration].
  /// If a custom Dio [client] is provided, Sonic will eagerly initialize with it.
  ///
  /// The optional [instanceTag] can be used to identify or log this instance.
  Sonic({
    required this.baseConfiguration,
    this.instanceTag,
    Dio? client,
  }) {
    // Optional eager init when custom client provided
    if (client != null) {
      initialize(client: client);
    }
  }

  /// Creates and initializes the client in one step.
  ///
  /// Equivalent to calling the default constructor and then [initialize].
  Sonic.initialize({
    required this.baseConfiguration,
    this.instanceTag,
    Dio? client,
  }) {
    initialize(client: client);
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
  late final CacheStore _cache;
  final Map<String, Future<Response<dynamic>>> _inFlight =
      <String, Future<Response<dynamic>>>{};
  // Per-host rate limiters constructed from BaseConfiguration.rateLimits
  final Map<String, TokenBucketLimiter> _limiters =
      <String, TokenBucketLimiter>{};
  CircuitBreaker? _circuit;
  // Template registry supports simple and argument-based templates.
  final Map<String, _Template> _templates = <String, _Template>{};

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

  /// Initializes the internal Dio client, caches, and policies.
  ///
  /// You must call this when using the default constructor without a [client].
  /// Otherwise, most operations will throw [ClientNotInitializedException].
  void initialize({Dio? client}) {
    if (_initialized) {
      return;
    }

    final options = baseConfiguration.toDioBaseOptions();

    _dioClient = client ?? Dio(options);
    _instanceTypeMap = TypeMap();
    // Register default identity decoders for common JSON shapes.
    // These act as sensible defaults and can be overridden by user registrations.
    _instanceTypeMap!.addDecoderForType<Map<String, dynamic>>(
        (j) => j as Map<String, dynamic>);
    _instanceTypeMap!
        .addDecoderForType<List<dynamic>>((j) => (j as List).cast<dynamic>());
    _instanceTypeMap!.addDecoderForType<String>((j) => j as String);
    _instanceTypeMap!.addDecoderForType<int>((j) => j as int);
    _instanceTypeMap!.addDecoderForType<double>((j) => (j as num).toDouble());
    _instanceTypeMap!.addDecoderForType<bool>((j) => j as bool);
    _cache = baseConfiguration.cacheStore ?? InMemoryCacheStore();

    // Build rate limiters from configuration (host -> config)
    final rl = baseConfiguration.rateLimits;
    if (rl != null && rl.isNotEmpty) {
      for (final entry in rl.entries) {
        _limiters[entry.key] = TokenBucketLimiter(entry.value);
      }
    }

    // Circuit breaker (optional)
    if (baseConfiguration.circuitBreakerConfig != null) {
      _circuit = CircuitBreaker(
        baseConfiguration.circuitBreakerConfig!,
        onEvent: baseConfiguration.onCircuitEvent,
      );
    }

    if (baseConfiguration.debugMode) {
      _client.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
        ),
      );
    }

    // Install token refresh interceptor if configured
    if (baseConfiguration.authRefresh != null) {
      final cfg = baseConfiguration.authRefresh!;
      _client.interceptors.add(
        AuthRefreshInterceptor(
          shouldRefresh: cfg.shouldRefresh,
          refresh: cfg.refresh,
          setAuthHeader: cfg.setAuthHeader,
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
      _typeMap.addEncoderForType<T>((dynamic v) => encoder(v as T));
    }
  }

  /// Register only a decoder for type [T]. Alias for [registerType] without encoder.
  void registerDecoder<T>(T Function(dynamic json) decoder) {
    _typeMap.addDecoderForType<T>(decoder);
  }

  /// Register both encoder and decoder for type [T].
  void registerJsonPair<T>({
    required Map<String, dynamic> Function(T instance) encoder,
    required T Function(dynamic json) decoder,
  }) {
    _typeMap.addJsonPairForType<T>(
      encoder: (dynamic v) => encoder(v as T),
      decoder: decoder,
    );
  }

  /// Returns true if a decoder is registered for type [T].
  bool hasDecoder<T>() => _typeMap.getDecoderForType<T>(false) != null;

  /// Unregister the decoder for type [T]. Returns true if it existed.
  bool unregisterDecoder<T>() {
    final exists = hasDecoder<T>();
    if (exists) {
      _typeMap.removeDecoderForType<T>();
    }
    return exists;
  }

  /// Start building a new request.
  ///
  /// Configure the returned builder and call [SonicRequestBuilder.execute]
  /// to perform the request.
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
    final startTime = DateTime.now();
    final cacheStart = DateTime.now();
    var attempts = 0;
    Response<dynamic> response;

    var _conditionalHeaders = <String, dynamic>{};
    CacheHit<dynamic>? _validatingHit;

    // Resolve effective base URL for this request and build absolute URL
    final _effectiveBase =
        _effectiveBaseUrlFor(requestBuilder as SonicRequestBuilder<dynamic>);
    final _requestUrl = _resolveRequestUrl(requestBuilder._url, _effectiveBase);

    Future<Response<dynamic>> makeRequest() {
      // Observability: onRequest hook
      baseConfiguration.onRequest?.call(
        RequestOptions(
          path: requestBuilder._url,
          method: requestBuilder._method.name,
          headers: {
            ...?requestBuilder._headers,
            ..._conditionalHeaders,
          },
          baseUrl: _effectiveBase,
          queryParameters: requestBuilder._queryParameters,
          data: requestBuilder._body,
        ),
      );
      return _client.request<dynamic>(
        _requestUrl,
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
          extra: <String, dynamic>{
            ...?requestBuilder._extra,
            'dio': _client,
          },
          headers: {
            ...?requestBuilder._headers,
            ..._conditionalHeaders,
          },
          responseType: requestBuilder._responseType,
          maxRedirects: requestBuilder._maxRedirects,
          followRedirects: requestBuilder._followRedirects,
          sendTimeout: requestBuilder._sentTimeout,
          receiveTimeout: requestBuilder._receiveTimeout,
          validateStatus: (code) =>
              code == 304 || (code != null && code >= 200 && code <= 299),
        ),
      );
    }

    // Cache key for GET requests
    final requestKey = _cache.makeKey(
      requestBuilder._method.name,
      _requestUrl,
      requestBuilder._queryParameters,
      requestBuilder._headers,
    );

    // Serve from cache first if enabled
    final useCache =
        requestBuilder._useCache && requestBuilder._method == HttpMethod.get;
    final ttl =
        requestBuilder._cachePolicy?.ttl ?? baseConfiguration.cachePolicy.ttl;
    final swrWindow = requestBuilder._cachePolicy?.staleWhileRevalidate ??
        baseConfiguration.cachePolicy.staleWhileRevalidate;
    int? cacheLookupMs;
    int? _cacheRevalidateMs;
    if (useCache) {
      // Fresh cache hit
      final freshHit = _cache.getWithMeta<dynamic>(requestKey, ttl);
      if (freshHit != null) {
        final mustValidate = freshHit.mustValidate == true;
        if (!mustValidate) {
          final decoder = requestBuilder._decoder;
          if (decoder == null && !rawRequest) {
            throw DecoderDoesNotExistException(
              message:
                  'Decoder for type ${typeOf<T>()} is not provided. Did you forgot to register a decoder?',
              stackTrace: StackTrace.current,
            );
          }
          return SonicResponse<T>._(
            statusCode: freshHit.statusCode,
            message: freshHit.message,
            data: rawRequest ? freshHit.data as T : decoder!(freshHit.data),
            headers: freshHit.headers,
            extra: <String, dynamic>{
              'durationMs': DateTime.now().difference(startTime).inMilliseconds,
              'cache': 'store',
              'cacheEvent': 'hit',
              'retries': 0,
              'retryDelaysMs': const <int>[],
              'deduplicated': false,
            },
          );
        } else {
          // Prepare conditional headers for revalidation now
          if (freshHit.etag != null) {
            _conditionalHeaders['If-None-Match'] = freshHit.etag;
          }
          if (freshHit.lastModified != null) {
            _conditionalHeaders['If-Modified-Since'] = freshHit.lastModified;
          }
          _validatingHit = freshHit;
        }
      }

      // Stale-while-revalidate: serve stale data if within window and refresh in background
      final staleHit = _cache.getIfWithin<dynamic>(requestKey, swrWindow);
      if (staleHit != null) {
        final mustValidate = staleHit.mustValidate == true;
        if (mustValidate) {
          // Can't serve stale, must revalidate synchronously
          if (staleHit.etag != null) {
            _conditionalHeaders['If-None-Match'] = staleHit.etag;
          }
          if (staleHit.lastModified != null) {
            _conditionalHeaders['If-Modified-Since'] = staleHit.lastModified;
          }
          _validatingHit = staleHit;
        } else {
          // Background refresh with If-None-Match
          final headers =
              Map<String, dynamic>.from(requestBuilder._headers ?? const {});
          if (staleHit.etag != null) {
            headers['If-None-Match'] = staleHit.etag;
          }
          if (staleHit.lastModified != null) {
            headers['If-Modified-Since'] = staleHit.lastModified;
          }
          final bgOptions = Options(
            method: requestBuilder._method.name,
            extra: requestBuilder._extra,
            headers: headers,
            maxRedirects: requestBuilder._maxRedirects,
            followRedirects: requestBuilder._followRedirects,
            sendTimeout: requestBuilder._sentTimeout,
            receiveTimeout: requestBuilder._receiveTimeout,
            validateStatus: (code) =>
                code == 304 || (code != null && code >= 200 && code <= 299),
          );
          final revalStart = DateTime.now();
          unawaited(_client
              .request<dynamic>(
            _requestUrl,
            data: requestBuilder._body,
            cancelToken: requestBuilder._cancelToken,
            queryParameters: requestBuilder._queryParameters,
            options: bgOptions,
          )
              .then((resp) {
            _cacheRevalidateMs =
                DateTime.now().difference(revalStart).inMilliseconds;
            if (resp.statusCode == 304) {
              Duration? perEntryTtl;
              final cc =
                  resp.headers.value('cache-control')?.toLowerCase() ?? '';
              final match = RegExp(r'max-age\s*=\s*(\d+)').firstMatch(cc);
              if (match != null) {
                final seconds = int.tryParse(match.group(1) ?? '');
                if (seconds != null) {
                  perEntryTtl = Duration(seconds: seconds);
                }
              }
              final mustValidateHeader =
                  cc.contains('no-cache') || cc.contains('must-revalidate');
              _cache.updateMeta(
                requestKey,
                headers: resp.headers.map,
                statusCode: resp.statusCode,
                message: resp.statusMessage,
                etag: resp.headers.value('etag'),
                ttl: perEntryTtl,
                lastModified: resp.headers.value('last-modified'),
                mustValidate: mustValidateHeader,
              );
            } else if (resp.statusCode != null &&
                resp.statusCode! >= 200 &&
                resp.statusCode! <= 299) {
              final dec = requestBuilder._decoder;
              final payload = rawRequest
                  ? resp.data as T
                  : (dec == null ? resp.data as T : dec(resp.data));
              final cc =
                  resp.headers.value('cache-control')?.toLowerCase() ?? '';
              final mustValidateHeader =
                  cc.contains('no-cache') || cc.contains('must-revalidate');
              Duration? perEntryTtl;
              final match = RegExp(r'max-age\s*=\s*(\d+)').firstMatch(cc);
              if (match != null) {
                final seconds = int.tryParse(match.group(1) ?? '');
                if (seconds != null) {
                  perEntryTtl = Duration(seconds: seconds);
                }
              }
              _cache.put<dynamic>(
                requestKey,
                payload,
                headers: resp.headers.map,
                statusCode: resp.statusCode ?? -1,
                message: resp.statusMessage,
                etag: resp.headers.value('etag'),
                lastModified: resp.headers.value('last-modified'),
                mustValidate: mustValidateHeader,
                ttl: perEntryTtl,
              );
            }
          }).catchError((_) {
            // Ignore background errors
          }));

          final decoder = requestBuilder._decoder;
          if (decoder == null && !rawRequest) {
            throw DecoderDoesNotExistException(
              message:
                  'Decoder for type ${typeOf<T>()} is not provided. Did you forgot to register a decoder?',
              stackTrace: StackTrace.current,
            );
          }
          return SonicResponse<T>._(
            statusCode: staleHit.statusCode,
            message: staleHit.message,
            data: rawRequest ? staleHit.data as T : decoder!(staleHit.data),
            headers: staleHit.headers,
            extra: <String, dynamic>{
              'durationMs': DateTime.now().difference(startTime).inMilliseconds,
              'cache': 'store',
              'cacheEvent': 'stale',
              'retries': 0,
              'retryDelaysMs': const <int>[],
              'deduplicated': false,
            },
          );
        }
      }
      cacheLookupMs = DateTime.now().difference(cacheStart).inMilliseconds;
    }

    final allowConcurrency = baseConfiguration.allowConcurrency;
    final retryOptions =
        requestBuilder._retryOptions ?? baseConfiguration.retryOptions;

    final _retryDelaysMs = <int>[];

    // Resolve host to select appropriate rate limiter (absolute URL wins)
    var _limiter = null as TokenBucketLimiter?;
    var host = '';
    try {
      final uri = Uri.tryParse(_requestUrl);
      host =
          (uri != null && uri.hasScheme && uri.host.isNotEmpty) ? uri.host : '';
      if (host.isNotEmpty) {
        _limiter = _limiters[host];
      }
    } catch (_) {
      // ignore host parsing failures; proceed without limiter
    }

    Future<Response<dynamic>> runWithPolicies() => _executeWithPolicies(
          effectiveFutureBuilder: () async {
            if (_limiter != null) {
              // await permit based on priority before making the request
              final rlStart = DateTime.now();
              await _limiter.acquire(priority: requestBuilder._priority);
              requestBuilder._rateLimitWaitMs =
                  DateTime.now().difference(rlStart).inMilliseconds;
            }
            // Circuit breaker check
            if (_circuit != null && host.isNotEmpty) {
              final key = host; // per-host circuit
              if (!_circuit!.allowRequest(key)) {
                throw CircuitOpenException('Circuit open for $key');
              }
            }
            return makeRequest();
          },
          retryOptions: retryOptions,
          methodName: requestBuilder._method.name,
          allowConcurrency: allowConcurrency,
          lock: _lock,
          onRetryScheduled: (d) => _retryDelaysMs.add(d.inMilliseconds),
        );

    // Deduplicate in-flight GET requests
    final dedup = (requestBuilder._deduplicate ??
            baseConfiguration.deduplicateRequests) &&
        requestBuilder._method == HttpMethod.get;
    final netStart = DateTime.now();
    if (dedup) {
      final existing = _inFlight[requestKey];
      if (existing != null) {
        response = await existing;
      } else {
        final future = runWithPolicies();
        _inFlight[requestKey] = future;
        try {
          response = await future;
        } finally {
          // ignore: unawaited_futures
          _inFlight.remove(requestKey);
        }
      }
    } else {
      response = await runWithPolicies();
    }
    attempts++; // Note: counts outer attempt; internal retries counted below
    final networkMs = DateTime.now().difference(netStart).inMilliseconds;

    // If server responded 304 to a conditional request, serve cached hit
    if (response.statusCode == 304 && _validatingHit != null) {
      // Update TTL/mustValidate from response headers
      final cc = response.headers.value('cache-control')?.toLowerCase() ?? '';
      Duration? perEntryTtl;
      final match = RegExp(r'max-age\s*=\s*(\d+)').firstMatch(cc);
      if (match != null) {
        final seconds = int.tryParse(match.group(1) ?? '');
        if (seconds != null) {
          perEntryTtl = Duration(seconds: seconds);
        }
      }
      final mustValidateHeader =
          cc.contains('no-cache') || cc.contains('must-revalidate');
      _cache.updateMeta(
        requestKey,
        headers: response.headers.map,
        statusCode: _validatingHit.statusCode,
        message: _validatingHit.message,
        etag: response.headers.value('etag') ?? _validatingHit.etag,
        lastModified: response.headers.value('last-modified') ??
            _validatingHit.lastModified,
        ttl: perEntryTtl,
        mustValidate: mustValidateHeader,
      );

      final decoder = requestBuilder._decoder;
      if (decoder == null && !rawRequest) {
        throw DecoderDoesNotExistException(
          message:
              'Decoder for type ${typeOf<T>()} is not provided. Did you forgot to register a decoder?',
          stackTrace: StackTrace.current,
        );
      }
      baseConfiguration.onResponse?.call(response);
      return SonicResponse<T>._(
        statusCode: _validatingHit.statusCode,
        message: _validatingHit.message,
        data: rawRequest
            ? _validatingHit.data as T
            : decoder!(_validatingHit.data),
        headers: _validatingHit.headers,
        extra: <String, dynamic>{
          'durationMs': DateTime.now().difference(startTime).inMilliseconds,
          'cache': 'validated-304',
          'cacheEvent': 'validated',
          'retries': attempts - 1,
          'retryDelaysMs': _retryDelaysMs,
          'deduplicated': false,
        },
      );
    }

    // Fallback: if 304 and validating hit missing, attempt to serve from cache
    if (response.statusCode == 304 && useCache) {
      final cc = response.headers.value('cache-control')?.toLowerCase() ?? '';
      Duration? perEntryTtl;
      final match = RegExp(r'max-age\s*=\s*(\d+)').firstMatch(cc);
      if (match != null) {
        final seconds = int.tryParse(match.group(1) ?? '');
        if (seconds != null) {
          perEntryTtl = Duration(seconds: seconds);
        }
      }
      final mustValidateHeader =
          cc.contains('no-cache') || cc.contains('must-revalidate');
      // Prefer fresh hit, otherwise stale within window
      final hit = _cache.getWithMeta<dynamic>(requestKey, ttl) ??
          _cache.getIfWithin<dynamic>(requestKey, swrWindow);
      if (hit != null) {
        _cache.updateMeta(
          requestKey,
          headers: response.headers.map,
          statusCode: hit.statusCode,
          message: hit.message,
          etag: response.headers.value('etag') ?? hit.etag,
          lastModified:
              response.headers.value('last-modified') ?? hit.lastModified,
          ttl: perEntryTtl,
          mustValidate: mustValidateHeader,
        );

        final decoder = requestBuilder._decoder;
        if (decoder == null && !rawRequest) {
          throw DecoderDoesNotExistException(
            message:
                'Decoder for type ${typeOf<T>()} is not provided. Did you forgot to register a decoder?',
            stackTrace: StackTrace.current,
          );
        }
        baseConfiguration.onResponse?.call(response);
        return SonicResponse<T>._(
          statusCode: hit.statusCode,
          message: hit.message,
          data: rawRequest ? hit.data as T : decoder!(hit.data),
          headers: hit.headers,
          extra: <String, dynamic>{
            'durationMs': DateTime.now().difference(startTime).inMilliseconds,
            'cache': 'validated-304',
            'cacheEvent': 'validated',
            'retries': attempts - 1,
            'retryDelaysMs': _retryDelaysMs,
            'deduplicated': false,
          },
        );
      }
    }

    final decoder = requestBuilder._decoder;
    final safeDecoder = requestBuilder._safeDecoder;

    if (decoder == null && safeDecoder == null && !rawRequest) {
      throw DecoderDoesNotExistException(
        message:
            'Decoder for type ${typeOf<T>()} is not provided. Did you forgot to register a decoder?',
        stackTrace: StackTrace.current,
      );
    }

    dynamic _applyPluck(dynamic data) {
      final path = requestBuilder._pluckPath;
      if (path == null || path.isEmpty) {
        return data;
      }
      final segments = path
          .split('.')
          .where((e) => e.trim().isNotEmpty)
          .toList(growable: false);
      dynamic current = data;
      for (final seg in segments) {
        final match = RegExp(r'^([^\[]+)(?:\[(\d+)\])?$').firstMatch(seg);
        if (match == null) {
          return null;
        }
        final key = match.group(1);
        final idxStr = match.group(2);
        if (key != null && key.isNotEmpty) {
          if (current is Map) {
            current = current[key];
          } else {
            return null;
          }
        }
        if (idxStr != null) {
          final i = int.tryParse(idxStr);
          if (i == null) {
            return null;
          }
          if (current is List && i >= 0 && i < current.length) {
            current = current[i];
          } else {
            return null;
          }
        }
      }
      return current;
    }

    if (!rawRequest && decoder != null) {
      final cachedDecoder = _typeMap.getDecoderForType<T>(false);
      if (cachedDecoder == null) {
        _typeMap.addDecoderForType<T>(decoder);
      }
    }

    final extraMap = <String, dynamic>{
      'durationMs': DateTime.now().difference(startTime).inMilliseconds,
      'cache': useCache ? 'store' : 'network',
      'cacheEvent': useCache ? 'hit' : 'network',
      'retries': attempts - 1,
      'retryDelaysMs': _retryDelaysMs,
      'deduplicated': dedup,
      'networkMs': networkMs,
      'requestUrl': _requestUrl,
    };
    if (requestBuilder._rateLimitWaitMs != null) {
      extraMap['rateLimitWaitMs'] = requestBuilder._rateLimitWaitMs;
    }
    if (requestBuilder._decodeMs != null) {
      extraMap['decodeMs'] = requestBuilder._decodeMs;
    }
    if (cacheLookupMs != null) {
      extraMap['cacheLookupMs'] = cacheLookupMs;
    }
    extraMap['cacheRevalidateMs'] = _cacheRevalidateMs;

    final built = SonicResponse<T>._(
      statusCode: response.statusCode ?? -1,
      message: response.statusMessage,
      data: () {
        final transformed = _applyPluck(response.data);
        if (rawRequest) {
          return transformed as T;
        }
        // Strict mode: media type + shape check
        final strictEnabled =
            requestBuilder._strict ?? baseConfiguration.decodeStrict;
        if (strictEnabled) {
          final allowed = (requestBuilder._allowedMediaTypes ??
                  baseConfiguration.allowedMediaTypes)
              .map((e) => e.toLowerCase())
              .toList();
          final ct = response.headers.value('content-type')?.toLowerCase();
          final mediaType = ct?.split(';').first.trim();
          final okType = mediaType != null && allowed.any(mediaType.startsWith);
          if (!okType) {
            throw DecoderDoesNotExistException(
              message: 'Disallowed content-type in strict mode: $ct',
              stackTrace: StackTrace.current,
            );
          }
          final d = transformed;
          var matches = true;
          if (T == Map<String, dynamic>) {
            matches = d is Map<String, dynamic>;
          } else if (T == List || T == List<dynamic>) {
            matches = d is List;
          } else if (T == String) {
            matches = d is String;
          } else if (T == int) {
            matches = d is int;
          } else if (T == double) {
            matches = d is num;
          } else if (T == bool) {
            matches = d is bool;
          }
          if (!matches) {
            throw DecoderDoesNotExistException(
              message:
                  'Strict mode shape mismatch: expected $T but got ${d.runtimeType}',
              stackTrace: StackTrace.current,
            );
          }
        }
        // Schema adapter
        final adapted = requestBuilder._schemaAdapter != null
            ? requestBuilder._schemaAdapter!(transformed)
            : transformed;
        // Type guard
        if (requestBuilder._typeGuard != null) {
          final r = requestBuilder._typeGuard!(adapted);
          if (!r.isOk) {
            if (safeDecoder != null) {
              // ignore: avoid_as
              return DecodeResult<T>(errors: r.errors) as T;
            }
            throw DecoderDoesNotExistException(
              message:
                  'Type guard failed with ${r.errors.length} error(s): ${r.errors.first.message}',
              stackTrace: StackTrace.current,
            );
          }
          if (r.value != null && decoder == null && safeDecoder == null) {
            return r.value as T;
          }
        }
        if (safeDecoder != null) {
          // ignore: avoid_as
          return safeDecoder(adapted) as T;
        }
        final dStart = DateTime.now();
        final val = decoder!(adapted);
        requestBuilder._decodeMs =
            DateTime.now().difference(dStart).inMilliseconds;
        return val;
      }(),
      headers: response.headers.map,
      extra: extraMap,
    );
    // Observability: onResponse hook
    baseConfiguration.onResponse?.call(response);
    // Store in cache if enabled and success
    if (useCache && built.isSuccess) {
      // Parse Cache-Control for header-aware caching
      final cc = response.headers.value('cache-control') ?? '';
      final lower = cc.toLowerCase();
      if (lower.contains('no-store')) {
        // Skip caching entirely
        return built;
      }
      final mustValidateHeader =
          lower.contains('no-cache') || lower.contains('must-revalidate');
      Duration? perEntryTtl;
      final match = RegExp(r'max-age\s*=\s*(\d+)').firstMatch(lower);
      if (match != null) {
        final seconds = int.tryParse(match.group(1) ?? '');
        if (seconds != null) {
          perEntryTtl = Duration(seconds: seconds);
        }
      }
      // Fallback to Expires header if no max-age
      if (perEntryTtl == null) {
        final expiresStr = response.headers.value('expires');
        if (expiresStr != null) {
          try {
            final expires = HttpDate.parse(expiresStr);
            final diff = expires.difference(DateTime.now());
            if (!diff.isNegative) {
              perEntryTtl = diff;
            }
          } catch (_) {}
        }
      }
      _cache.put<dynamic>(
        requestKey,
        (() {
          final transformed = _applyPluck(response.data);
          if (rawRequest) {
            return transformed as T;
          }
          final adapted = requestBuilder._schemaAdapter != null
              ? requestBuilder._schemaAdapter!(transformed)
              : transformed;
          if (safeDecoder != null) {
            return safeDecoder(adapted);
          }
          return decoder!(adapted);
        })(),
        headers: response.headers.map,
        statusCode: response.statusCode ?? -1,
        message: response.statusMessage,
        etag: response.headers.value('etag'),
        lastModified: response.headers.value('last-modified'),
        mustValidate: mustValidateHeader,
        ttl: perEntryTtl,
      );
    }
    // Circuit accounting: record success/failure
    if (_circuit != null && host.isNotEmpty) {
      final key = host;
      if (built.isSuccess) {
        _circuit!.recordSuccess(key);
      } else {
        _circuit!.recordFailure(key);
      }
    }
    return built;
  }

  Future<SonicResponse<void>> _runDownload(
    SonicRequestBuilder<dynamic> requestBuilder,
    String savePath,
  ) async {
    final startTime = DateTime.now();
    try {
      final _effectiveBase = _effectiveBaseUrlFor(requestBuilder);
      final _requestUrl =
          _resolveRequestUrl(requestBuilder._url, _effectiveBase);
      // Observability: onRequest hook
      baseConfiguration.onRequest?.call(
        RequestOptions(
          path: requestBuilder._url,
          method: requestBuilder._method.name,
          headers: requestBuilder._headers,
          baseUrl: _effectiveBase,
          queryParameters: requestBuilder._queryParameters,
          data: requestBuilder._body,
        ),
      );
      final resp = await _client.download(
        _requestUrl,
        savePath,
        data: requestBuilder._body,
        cancelToken: requestBuilder._cancelToken,
        queryParameters: requestBuilder._queryParameters,
        onReceiveProgress: (count, total) {
          if (requestBuilder._receiveProgress != null) {
            requestBuilder._receiveProgress!(
              SonicProgress(current: count, total: total),
            );
          }
        },
        options: Options(
          method: requestBuilder._method.name,
          headers: requestBuilder._headers,
          extra: <String, dynamic>{
            ...?requestBuilder._extra,
            'dio': _client,
          },
          maxRedirects: requestBuilder._maxRedirects,
          followRedirects: requestBuilder._followRedirects,
          sendTimeout: requestBuilder._sentTimeout,
          receiveTimeout: requestBuilder._receiveTimeout,
        ),
      );
      baseConfiguration.onResponse?.call(resp);
      return SonicResponse<void>._(
        statusCode: resp.statusCode ?? -1,
        headers: resp.headers.map,
        message: resp.statusMessage,
        extra: <String, dynamic>{
          'durationMs': DateTime.now().difference(startTime).inMilliseconds,
          'cache': 'network',
          'cacheEvent': 'network',
          'retries': 0,
          'retryDelaysMs': const <int>[],
          'deduplicated': false,
          'downloadPath': savePath,
        },
      );
    } on DioException catch (e) {
      baseConfiguration.onError?.call(e);
      return SonicResponse<void>._(
        statusCode: -1,
        sonicError: SonicError(
          message: e.message ?? 'DioException',
          stackTrace: e.stackTrace as StackTrace? ?? StackTrace.current,
        ),
      );
    }
  }

  Future<Response<dynamic>> _executeWithPolicies({
    required Future<Response<dynamic>> Function() effectiveFutureBuilder,
    required RetryOptions retryOptions,
    required String methodName,
    required bool allowConcurrency,
    required sync.Lock? lock,
    void Function(Duration delay)? onRetryScheduled,
  }) async {
    var attempt = 1;
    while (true) {
      try {
        if (!allowConcurrency && lock != null) {
          return await lock.synchronized(() async => effectiveFutureBuilder());
        }
        return await effectiveFutureBuilder();
      } on DioException catch (e) {
        final response = e.response;
        if (!retryOptions.shouldAttemptRetry(
          attempt: attempt,
          method: methodName,
          response: response,
          error: e,
        )) {
          baseConfiguration.onError?.call(e);
          rethrow;
        }
        final delay = retryOptions.computeDelay(attempt, response: response);
        if (onRetryScheduled != null) {
          onRetryScheduled(delay);
        }
        await Future<void>.delayed(delay);
        attempt++;
        // fallthrough to retry
        continue;
      }
    }
  }

  /// Add a Dio interceptor to this client's pipeline.
  void addInterceptor(Interceptor interceptor) {
    _client.interceptors.add(interceptor);
  }

  /// Add multiple Dio interceptors.
  void addInterceptors(Iterable<Interceptor> interceptors) {
    _client.interceptors.addAll(interceptors);
  }

  /// Register a reusable request template function that modifies a builder.
  void registerTemplate(
      String name, void Function(SonicRequestBuilder<dynamic>) apply) {
    _templates[name] = _Template.apply(apply);
  }

  /// Register a template that accepts an argument payload.
  /// Use with [templateWith] or [SonicRequestBuilder.applyTemplateWith].
  void registerTemplateWith<A>(
      String name, void Function(SonicRequestBuilder<dynamic>, A args) apply) {
    _templates[name] = _Template.applyWithArgs((b, dynamic a) {
      // Cast to A; will throw if caller provided mismatched type.
      // ignore: avoid_as
      return apply(b, a as A);
    });
  }

  /// Start a builder from a previously registered template.
  SonicRequestBuilder<T> template<T>(String name,
      {required String url, HttpMethod method = HttpMethod.get}) {
    final base = create<T>(url: url, method: method);
    final t = _templates[name];
    if (t != null) {
      t(base as SonicRequestBuilder<dynamic>);
    }
    return base;
  }

  /// Start a builder from a template that expects an argument.
  SonicRequestBuilder<T> templateWith<T, A>(String name, A args,
      {required String url, HttpMethod method = HttpMethod.get}) {
    final base = create<T>(url: url, method: method);
    final t = _templates[name];
    if (t != null) {
      t(base as SonicRequestBuilder<dynamic>, args);
    }
    return base;
  }

  /// Return true if a template name is registered.
  bool hasTemplate(String name) => _templates.containsKey(name);

  /// List all registered template names.
  Iterable<String> listTemplates() => _templates.keys;

  /// Unregister a template by name. Returns true if removed.
  bool unregisterTemplate(String name) => _templates.remove(name) != null;

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

  // Resolve effective baseUrl for a given request builder, honoring per-request
  // api version selection when BaseConfiguration.apiVersions is provided.
  String _effectiveBaseUrlFor(SonicRequestBuilder<dynamic> rb) {
    final versions = baseConfiguration.apiVersions;
    final selected = rb._apiVersion;
    final defaultBase = baseConfiguration.toDioBaseOptions().baseUrl;
    if (versions != null && selected != null) {
      final mapped = versions[selected];
      if (mapped != null && mapped.isNotEmpty) {
        // Replace placeholders using values derived from the configured base URL
        final u = Uri.tryParse(defaultBase);
        final scheme = u?.scheme ?? '';
        final host = u?.host ?? '';
        final hasPort = u != null && u.hasPort && u.port != 0;
        final port = hasPort ? u.port.toString() : '';
        final origin = (scheme.isNotEmpty && host.isNotEmpty)
            ? '$scheme://$host${hasPort ? ':$port' : ''}'
            : defaultBase;
        final basePath = u?.path ?? '';
        var replaced = mapped
            .replaceAll('{baseUrl}', defaultBase)
            .replaceAll('{scheme}', scheme)
            .replaceAll('{host}', host)
            .replaceAll('{port}', port)
            .replaceAll('{origin}', origin)
            .replaceAll('{basePath}', basePath)
            .replaceAll('{version}', selected);
        // Placeholder resolution pass for custom tokens, e.g., {env:FOO}
        final baseUri = u ?? Uri();
        // Built-in tokens already replaced above; match any tokens that remain
        final re = RegExp(r'\{([a-zA-Z0-9_\-]+)(?::([^}]+))?\}');
        return replaced.replaceAllMapped(re, (m) {
          final token = m.group(0)!;
          final name = m.group(1)!;
          final arg = m.group(2);
          // Skip built-ins we already handled
          const builtins = {
            'baseUrl',
            'scheme',
            'host',
            'port',
            'origin',
            'basePath',
            'version',
          };
          if (builtins.contains(name)) {
            return token;
          }
          // Default env resolvers (opt-in via flags)
          String? resolved;
          if (name == 'env' && arg != null) {
            if (baseConfiguration.envPlaceholdersFromDartDefines) {
              // Note: String.fromEnvironment reads compile-time defines; returns empty if unset.
              // ignore: do_not_use_environment
              final v = String.fromEnvironment(arg);
              if (v.isNotEmpty) {
                resolved = v;
              }
            }
            if (resolved == null &&
                baseConfiguration.envPlaceholdersFromProcessEnv) {
              try {
                // Access Platform.environment only when enabled
                // ignore: avoid_dynamic_calls
                final plat = Platform.environment;
                final v = plat[arg];
                if (v != null && v.isNotEmpty) {
                  resolved = v;
                }
              } catch (_) {
                // Platform may not be available in some runtimes; ignore
              }
            }
          }
          // User resolver has the final say if provided
          final user = baseConfiguration.apiVersionPlaceholderResolver;
          if (user != null) {
            resolved = user(name, arg, baseUri, selected) ?? resolved;
          }
          return resolved ?? token;
        });
      }
    }
    return defaultBase;
  }

  // Resolve a possibly relative request path against a base URL.
  // If the provided url is already absolute, it is returned as-is.
  String _resolveRequestUrl(String urlOrPath, String baseUrl) {
    final uri = Uri.tryParse(urlOrPath);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return urlOrPath; // already absolute
    }
    if (baseUrl.isEmpty) {
      return urlOrPath;
    }
    return Uri.parse(baseUrl).resolve(urlOrPath).toString();
  }
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
  // Optional selected API version key for per-request base URL override.
  String? _apiVersion;
  Map<String, dynamic>? _headers;
  Map<String, dynamic>? _extra;
  dynamic _body;
  Map<String, dynamic>? _queryParameters;
  T Function(dynamic json)? _decoder;
  DecodeResult<T> Function(dynamic json)? _safeDecoder;
  CancelToken? _cancelToken;
  bool? _followRedirects;
  int? _maxRedirects;
  Duration? _receiveTimeout;
  Duration? _sentTimeout;
  SonicProgressCallback? _sentProgress;
  SonicProgressCallback? _receiveProgress;
  void Function(SonicError error)? _onError;
  void Function()? _onRunning;
  void Function(SonicResponse<T> data)? _onSuccess;
  bool _useCache = false;
  CachePolicy? _cachePolicy;
  bool? _deduplicate;
  RetryOptions? _retryOptions;
  String? _pluckPath;
  ResponseType? _responseType;
  String? _correlationId;
  FormData? _formData;
  RequestPriority _priority = RequestPriority.normal;
  int? _rateLimitWaitMs;
  int? _decodeMs;
  // Strict mode and validation hooks
  bool? _strict; // null -> use BaseConfiguration.decodeStrict
  List<String>?
      _allowedMediaTypes; // null -> use BaseConfiguration.allowedMediaTypes
  DecodeResult<T> Function(dynamic json)? _typeGuard;
  dynamic Function(dynamic json)? _schemaAdapter;

  void _ensureFormData() {
    if (_formData != null) {
      _body = _formData;
      return;
    }
    if (_body is FormData) {
      _formData = _body as FormData;
    } else if (_body is Map<String, dynamic>) {
      _formData = FormData.fromMap(
        Map<String, dynamic>.from(_body as Map),
      );
    } else {
      _formData = FormData();
    }
    _body = _formData;
  }

  /// Apply a named template to this builder.
  SonicRequestBuilder<T> applyTemplate(String name) {
    final t = _sonic._templates[name];
    if (t != null) {
      t(this as SonicRequestBuilder<dynamic>);
    }
    return this;
  }

  /// Apply a named template with argument to this builder.
  SonicRequestBuilder<T> applyTemplateWith<A>(String name, A args) {
    final t = _sonic._templates[name];
    if (t != null) {
      t(this as SonicRequestBuilder<dynamic>, args);
    }
    return this;
  }

  /// Apply multiple templates in order.
  SonicRequestBuilder<T> applyTemplates(Iterable<String> names) {
    for (final n in names) {
      final t = _sonic._templates[n];
      if (t != null) {
        t(this as SonicRequestBuilder<dynamic>);
      }
    }
    return this;
  }

  /// Provide a typed decoder for responses of type [T].
  ///
  /// Notes:
  /// - Decoders are cached per type in this [Sonic] instance.
  /// - If you previously called [Sonic.registerType], you usually don't need to set it again.
  SonicRequestBuilder<T> withDecoder(T Function(dynamic json) decoder) {
    _decoder = decoder;
    return this;
  }

  /// Provide a safe decoder that returns [DecodeResult] instead of throwing.
  SonicRequestBuilder<T> withSafeDecoder(
      DecodeResult<T> Function(dynamic json) decoder) {
    _safeDecoder = decoder;
    return this;
  }

  /// Override strict decoding behavior and optionally allowed content types.
  SonicRequestBuilder<T> strict({bool? enabled, List<String>? allowedTypes}) {
    _strict = enabled;
    _allowedMediaTypes = allowedTypes;
    return this;
  }

  /// Provide a type guard to validate JSON before decoding.
  SonicRequestBuilder<T> withTypeGuard(
      DecodeResult<T> Function(dynamic json) guard) {
    _typeGuard = guard;
    return this;
  }

  /// Provide a schema adapter to transform JSON before decoding.
  SonicRequestBuilder<T> withSchemaAdapter(dynamic Function(dynamic json) f) {
    _schemaAdapter = f;
    return this;
  }

  /// Treat this request as multipart/form-data and initialize a [FormData] body.
  /// If the current body is a map, it will be converted to [FormData].
  SonicRequestBuilder<T> asMultipart() {
    _ensureFormData();
    return this;
  }

  /// Convenience for uploads. Ensures multipart and defaults to POST if method was GET.
  SonicRequestBuilder<T> upload() {
    if (_method == HttpMethod.get) {
      _method = HttpMethod.post;
    }
    return asMultipart();
  }

  /// Add a single text field to multipart body.
  SonicRequestBuilder<T> field(String key, Object? value) {
    _ensureFormData();
    _formData!.fields.add(MapEntry(key, value?.toString() ?? ''));
    return this;
  }

  /// Add multiple fields/files to multipart body.
  /// If any values are MultipartFile/List<MultipartFile>, they are preserved as files.
  SonicRequestBuilder<T> fields(Map<String, dynamic> map) {
    _ensureFormData();
    final fd = FormData.fromMap(map);
    _formData!.fields.addAll(fd.fields);
    _formData!.files.addAll(fd.files);
    return this;
  }

  /// Add multiple files under the same field name.
  SonicRequestBuilder<T> files(String field, List<MultipartFile> files) {
    _ensureFormData();
    for (final f in files) {
      _formData!.files.add(MapEntry(field, f));
    }
    return this;
  }

  /// Attach a file from disk to multipart body (synchronous variant).
  SonicRequestBuilder<T> fileFromPath(
    String field,
    String filePath, {
    String? filename,
    MediaType? contentType,
  }) {
    _ensureFormData();
    final inferred =
        contentType ?? _inferMediaType(filename ?? p.basename(filePath));
    final mf = MultipartFile.fromFileSync(
      filePath,
      filename: filename,
      contentType: inferred,
    );
    _formData!.files.add(MapEntry(field, mf));
    return this;
  }

  /// Attach a file from bytes to multipart body.
  SonicRequestBuilder<T> fileFromBytes(
    String field,
    List<int> bytes, {
    String? filename,
    MediaType? contentType,
  }) {
    _ensureFormData();
    final inferred = contentType ?? _inferMediaType(filename);
    final mf = MultipartFile.fromBytes(
      bytes,
      filename: filename,
      contentType: inferred,
    );
    _formData!.files.add(MapEntry(field, mf));
    return this;
  }

  /// Attach a file from a byte stream to multipart body.
  SonicRequestBuilder<T> fileFromStream(
    String field,
    Stream<List<int>> Function() stream,
    int length, {
    String? filename,
    MediaType? contentType,
  }) {
    _ensureFormData();
    final inferred = contentType ?? _inferMediaType(filename);
    final mf = MultipartFile.fromStream(
      stream,
      length,
      filename: filename,
      contentType: inferred,
    );
    _formData!.files.add(MapEntry(field, mf));
    return this;
  }

  /// Alias for withSentProgress.
  SonicRequestBuilder<T> onUploadProgress(SonicProgressCallback cb) =>
      withSentProgress(cb);

  /// Alias for withReceiveProgress.
  SonicRequestBuilder<T> onDownloadProgress(SonicProgressCallback cb) =>
      withReceiveProgress(cb);

  MediaType? _inferMediaType(String? filename) {
    if (filename == null || filename.isEmpty) {
      return null;
    }
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.png':
        return MediaType('image', 'png');
      case '.jpg':
      case '.jpeg':
        return MediaType('image', 'jpeg');
      case '.gif':
        return MediaType('image', 'gif');
      case '.webp':
        return MediaType('image', 'webp');
      case '.json':
        return MediaType('application', 'json');
      case '.pdf':
        return MediaType('application', 'pdf');
      case '.zip':
        return MediaType('application', 'zip');
      case '.txt':
        return MediaType('text', 'plain');
      case '.csv':
        return MediaType('text', 'csv');
      case '.mp4':
        return MediaType('video', 'mp4');
      case '.mp3':
        return MediaType('audio', 'mpeg');
      default:
        return null;
    }
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
    _receiveTimeout = Duration(milliseconds: timeout);
    return this;
  }

  /// Specifies a sent timeout for this request.
  SonicRequestBuilder<T> withSendTimeout(int timeout) {
    _sentTimeout = Duration(milliseconds: timeout);
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

  /// Set ResponseType for this request (e.g., ResponseType.json/bytes/stream/plain)
  SonicRequestBuilder<T> withResponseType(ResponseType type) {
    _responseType = type;
    return this;
  }

  /// Marks the request as a Raw Request. (No typed decoding)
  SonicRequestBuilder<T> asRawRequest() {
    _rawRequest = true;
    return this;
  }

  /// Enable simple in-memory GET cache for this request.
  /// Note: if [pluck] is set for a GET, caching is disabled to avoid mixing shapes.
  SonicRequestBuilder<T> cache({CachePolicy? policy}) {
    // If a pluck path is set on a GET, avoid enabling cache to prevent
    // mixing cached shapes with different pluck paths.
    if (_method == HttpMethod.get && _pluckPath != null) {
      return this;
    }
    _useCache = true;
    _cachePolicy = policy;
    return this;
  }

  /// Enable/disable request deduplication for this request.
  SonicRequestBuilder<T> deduplicate({bool enabled = true}) {
    _deduplicate = enabled;
    return this;
  }

  /// Override retry options for this request.
  SonicRequestBuilder<T> withRetryOptions(RetryOptions options) {
    _retryOptions = options;
    return this;
  }

  /// Attach arbitrary extra data to the request (available on Dio response/options).
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

  /// Map a Dart object into query parameters using a provided encoder.
  SonicRequestBuilder<T> withQueryObject<O>(
    O object,
    Map<String, dynamic> Function(O obj) encoder,
  ) {
    return withQueryParameters(encoder(object));
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

  /// Quickly add a Bearer Authorization header.
  SonicRequestBuilder<T> withBearerToken(String token) {
    return withHeader('Authorization', 'Bearer $token');
  }

  /// Add an Idempotency-Key header. If not provided, a simple unique key is generated.
  SonicRequestBuilder<T> withIdempotencyKey([String? key]) {
    key ??=
        'idemp-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
    return withHeader('Idempotency-Key', key);
  }

  /// Callback triggered when the data is received and the status code indicates success.
  SonicRequestBuilder<T> onSuccess(
    void Function(SonicResponse<T> data) callback,
  ) {
    _onSuccess = callback;
    return this;
  }

  /// Callback triggered when there is an error with the requesting process.
  /// Errors are reported as [SonicError] with message and stackTrace.
  SonicRequestBuilder<T> onError(void Function(SonicError error) callback) {
    _onError = callback;
    return this;
  }

  /// Callback triggered when the request is in progress.
  SonicRequestBuilder<T> onLoading(void Function() callback) {
    _onRunning = callback;
    return this;
  }

  /// Pluck a nested value from the JSON payload before decoding.
  /// Example: 'data.items[0].user'. Disables GET cache for this request to avoid mixing cached shapes.
  SonicRequestBuilder<T> pluck(String path) {
    _pluckPath = path;
    if (_method == HttpMethod.get) {
      _useCache = false; // avoid caching typed, plucked payload
    }
    return this;
  }

  /// Alias for pluck when unwrapping common envelopes like 'data'.
  SonicRequestBuilder<T> envelope(String key) => pluck(key);

  /// Provide a correlation/request ID header. If omitted, generates one.
  SonicRequestBuilder<T> withCorrelationId([String? id]) {
    _correlationId = id ??
        'corr-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
    return withHeader('X-Correlation-ID', _correlationId!);
  }

  /// Set typed body using a provided encoder for a Dart object.
  SonicRequestBuilder<T> withBodyObject<O>(
    O object,
    Map<String, dynamic> Function(O obj) encoder,
  ) {
    return withBody(encoder(object));
  }

  /// Set scheduling priority for this request (affects rate limiting wait time).
  SonicRequestBuilder<T> withPriority(RequestPriority priority) {
    _priority = priority;
    return this;
  }

  /// Execute the request with the configured parameters.
  /// Returns a [SonicResponse] with typed data and useful metadata in `extra`.
  Future<SonicResponse<T>> execute() async {
    SonicError? errorObject;

    if (_onRunning != null) {
      _onRunning!();
    }

    final response = await tryCatchDelegate<SonicResponse<T>>(
      tryBlock: () async => _sonic._runRequest<T>(this, _rawRequest),
      fac: () {
        return SonicResponse._(
          statusCode: -1,
          sonicError: errorObject,
        );
      },
      exceptionCallback: (dynamic error, stackTrace) {
        if (error is DioException) {
          errorObject = SonicError(
            message: error.message ?? 'DioException',
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

  /// Download helper that writes response directly to [savePath].
  Future<SonicResponse<void>> downloadTo(String savePath) async {
    return _sonic._runDownload(this as SonicRequestBuilder<dynamic>, savePath);
  }

  /// Use a configured API version for this request. The version key must exist
  /// in BaseConfiguration.apiVersions. If not found, the default baseUrl is used.
  SonicRequestBuilder<T> useApiVersion(String versionKey) {
    _apiVersion = versionKey;
    return this;
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

/// Internal template wrapper that supports optional argument payloads.
class _Template {
  _Template.apply(this._apply) : _applyWithArgs = null;
  _Template.applyWithArgs(this._applyWithArgs) : _apply = null;

  final void Function(SonicRequestBuilder<dynamic> b)? _apply;
  final void Function(SonicRequestBuilder<dynamic> b, dynamic args)?
      _applyWithArgs;

  void call(SonicRequestBuilder<dynamic> b, [dynamic args]) {
    if (_applyWithArgs != null) {
      _applyWithArgs!(b, args);
    } else {
      _apply!(b);
    }
  }
}
