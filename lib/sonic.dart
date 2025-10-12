/// **Sonic** is a HTTP client made on top of **Dio** to have better support for types and provide a fluent interface for the calls.
library sonic;

export 'package:dio/dio.dart'
    show FormData, MultipartFile, CancelToken, ResponseType;
export 'package:http_parser/http_parser.dart' show MediaType;

export 'src/auth_refresh_interceptor.dart'
    show AuthRefreshInterceptor, SimpleAuthRefreshConfig;
export 'src/base_configuration.dart' show BaseConfiguration;
export 'src/cache.dart' show CachePolicy;
export 'src/circuit_breaker.dart' show CircuitBreakerConfig, CircuitState;
export 'src/composite_cache_store.dart' show CompositeCacheStore;
export 'src/decoding.dart' show DecodeResult, DecodeError, safeDecoder;
export 'src/enums.dart' show RequestPriority;
export 'src/file_cache_store.dart' show FileCacheStore;
export 'src/pagination.dart'
    show
        Paged,
        SonicPageRef,
        parseLinkHeader,
        parseLinkHeaderFromMap,
        pluckValue,
        addOrReplaceQueryParam,
        advanceOffsetLimit,
        advancePageNumber,
        makePaged;
export 'src/rate_limit.dart' show RateLimitConfig;
export 'src/retry_options.dart' show RetryOptions;
export 'src/sonic_base.dart' show Sonic, SonicRequestBuilder, SonicResponse;
