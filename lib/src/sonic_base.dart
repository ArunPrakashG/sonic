// ignore_for_file: public_member_api_docs, sort_constructors_first
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes, avoid_returning_this

import 'dart:async' show unawaited;
import 'dart:io' show HttpDate;
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
    Dio? client,
  }) {
    // Optional eager init when custom client provided
    if (client != null) {
      initialize(client: client);
    }
  }

  /// Named Consturctor which calls [initialize] method as well.
  ///
  /// [BaseConfiguration] is used to configure this instance of [Sonic]
  ///
  /// [instanceTag] is used to identify an instance of [Sonic]
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
  final Map<String, void Function(SonicRequestBuilder<dynamic>)> _templates =
      <String, void Function(SonicRequestBuilder<dynamic>)>{};

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
  void initialize({Dio? client}) {
    if (_initialized) {
      return;
    }

    final options = baseConfiguration.toDioBaseOptions();

    _dioClient = client ?? Dio(options);
    _instanceTypeMap = TypeMap();
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
    final startTime = DateTime.now();
    final cacheStart = DateTime.now();
    var attempts = 0;
    Response<dynamic> response;

    var _conditionalHeaders = <String, dynamic>{};
    CacheHit<dynamic>? _validatingHit;

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
          baseUrl: baseConfiguration.toDioBaseOptions().baseUrl,
          queryParameters: requestBuilder._queryParameters,
          data: requestBuilder._body,
        ),
      );
      return _client.request<dynamic>(
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
      requestBuilder._url,
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
            requestBuilder._url,
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
      final uri = Uri.tryParse(requestBuilder._url);
      final baseUrl = baseConfiguration.toDioBaseOptions().baseUrl;
      host = (uri != null && uri.hasScheme && uri.host.isNotEmpty)
          ? uri.host
          : (Uri.tryParse(baseUrl)?.host ?? '');
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
      'requestUrl': requestBuilder._url,
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
        if (safeDecoder != null) {
          // ignore: avoid_as
          return safeDecoder(transformed) as T;
        }
        final dStart = DateTime.now();
        final val = decoder!(transformed);
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
          if (safeDecoder != null) {
            return safeDecoder(transformed);
          }
          return decoder!(transformed);
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
      // Observability: onRequest hook
      baseConfiguration.onRequest?.call(
        RequestOptions(
          path: requestBuilder._url,
          method: requestBuilder._method.name,
          headers: requestBuilder._headers,
          baseUrl: baseConfiguration.toDioBaseOptions().baseUrl,
          queryParameters: requestBuilder._queryParameters,
          data: requestBuilder._body,
        ),
      );
      final resp = await _client.download(
        requestBuilder._url,
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
    _templates[name] = apply;
  }

  /// Start a builder from a previously registered template.
  SonicRequestBuilder<T> template<T>(String name,
      {required String url, HttpMethod method = HttpMethod.get}) {
    final base = create<T>(url: url, method: method);
    final fn = _templates[name];
    if (fn != null) {
      fn(base as SonicRequestBuilder<dynamic>);
    }
    return base;
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

  /// Adds a response decoder which decodes the response to the specified type.
  ///
  /// **NOTES**</br>
  /// - If you have already used the same model with another request, the decoder will be cached and therefore, you don't need to pass it again.
  /// - If you have used the `registerType()` method, you don't need to pass a decoder here either.
  SonicRequestBuilder<T> withDecoder(T Function(dynamic json) decoder) {
    _decoder = decoder;
    return this;
  }

  SonicRequestBuilder<T> withSafeDecoder(
      DecodeResult<T> Function(dynamic json) decoder) {
    _safeDecoder = decoder;
    return this;
  }

  /// Marks this request as multipart/form-data and initializes a FormData body.
  /// If an existing body map is present, it's converted into FormData.
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

  /// Marks the request as a Raw Request. (No Response Type Parsing)
  SonicRequestBuilder<T> asRawRequest() {
    _rawRequest = true;
    return this;
  }

  /// Enable simple in-memory GET cache for this request.
  SonicRequestBuilder<T> cache({CachePolicy? policy}) {
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

  /// Pluck a nested value from the JSON payload before decoding.
  /// Example: 'data.items[0].user'
  /// Note: Disables GET cache for this request to avoid mixing cached shapes.
  SonicRequestBuilder<T> pluck(String path) {
    _pluckPath = path;
    if (_method == HttpMethod.get) {
      _useCache = false; // avoid caching typed, plucked payload
    }
    return this;
  }

  /// Alias for pluck when unwrapping common envelopes like 'data'
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

  /// Called to execute the request with the parameters.
  ///
  /// The result `Future` contains [SonicResponse] which contains the response instance and meta data on the request.
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
