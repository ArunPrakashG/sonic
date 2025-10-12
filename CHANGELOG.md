## 1.3.0 - 2025-10-12

Interface-based Auth Refresh System with Custom Handler Support

Breaking changes:

- `AuthRefreshInterceptor` now accepts an `IAuthRefreshHandler` interface instead of individual callback parameters. If you were manually creating `AuthRefreshInterceptor` instances (not common), wrap your callbacks in `DefaultAuthRefreshHandler`:

  ```dart
  // Before
  AuthRefreshInterceptor(
    shouldRefresh: (err) => err.response?.statusCode == 401,
    refresh: () async => token,
    setAuthHeader: (req, token) => req.headers['Authorization'] = 'Bearer $token',
  )

  // After
  AuthRefreshInterceptor(
    handler: DefaultAuthRefreshHandler(
      shouldRefresh: (err) => err.response?.statusCode == 401,
      refresh: () async => token,
      setAuthHeader: (req, token) => req.headers['Authorization'] = 'Bearer $token',
    ),
  )
  ```

- **No changes needed** if you use `SimpleAuthRefreshConfig` in `BaseConfiguration` - it continues to work as before.

New/Improvements:

- **`IAuthRefreshHandler` interface** - Implement custom auth refresh logic with full control:
  - `shouldRefresh(DioException)` - Determine if refresh is needed
  - `refreshToken()` - Perform token refresh operation
  - `setAuthHeader(RequestOptions, String)` - Set authorization header
  - `onRefreshSuccess(String)` - Optional hook called after successful refresh
  - `onRefreshError(dynamic)` - Optional hook called when refresh fails
- **`DefaultAuthRefreshHandler`** - Default implementation using callback functions
- **Enhanced `SimpleAuthRefreshConfig`** - Added optional `onSuccess` and `onError` callbacks for lifecycle management
- **Better extensibility** - Easily implement custom refresh logic with retry mechanisms, token persistence, logging, and automatic logout
- **Improved testability** - Mock `IAuthRefreshHandler` in tests instead of individual callbacks
- **Type safety** - Interface ensures all required methods are implemented

Examples:

- Added `example/custom_auth_handler_example.dart` demonstrating all three approaches (SimpleAuthRefreshConfig, custom handler, DefaultAuthRefreshHandler)
- Added `example/production_auth_handler_example.dart` showing production-ready implementation with:
  - Retry logic with exponential backoff
  - Token persistence to secure storage
  - Refresh loop prevention
  - Automatic logout on permanent failure
  - Refresh token rotation support

Docs:

- Updated `wiki/AuthRefresh.md` with comprehensive examples of interface-based approach
- Added `AUTH_REFRESH_REFACTORING.md` migration guide
- All existing examples and tests updated to use new API

Internal:

- All 71 tests pass with new implementation
- Backward compatibility maintained through `SimpleAuthRefreshConfig.toHandler()`
- Zero breaking changes for users of `SimpleAuthRefreshConfig`

## 1.2.0 - 2025-10-12

Fluent API polish, Dockerized benchmarks, and docs refresh

Breaking changes:

- Fluent builder now uses consistent `withX` naming. The older non-`with` methods (e.g., `get()`, `post()`, `cache()`, `deduplicate()`, `upload()`, `asMultipart()`, `pluck()`, `envelope()`, `strict()`, `onSuccess()`/`onError()`/`onLoading()`, etc.) have been removed. Migrate to:
  - HTTP verb: `.withMethod(HttpMethod.get)`
  - Raw request: `.withRawRequest()`
  - Cache: `.withCache()`
  - Deduplication: `.withDeduplication()`
  - Uploads: `.withUpload()`, `.withMultipart()`, `.withField()`, `.withFields()`, `.withFiles()`, `.withFileFromPath()`, `.withFileFromBytes()`, `.withFileFromStream()`
  - Shaping: `.withPluck()`, `.withEnvelope()`
  - Strict/guards/adapters: `.withStrict()`, `.withTypeGuard()`, `.withSchemaAdapter()`
  - Callbacks: `.withOnSuccess()`, `.withOnError()`, `.withOnLoading()`
  - Redirects/limits: `.withFollowRedirects([bool])`, `.withMaxRedirects()`
  - API versioning: `.withApiVersion('v2')`

New/Improvements:

- Public export of `HttpMethod` from `package:sonic/sonic.dart` for cleaner usage in apps and examples.
- Added Docker-based benchmark workflow and script `scripts/run_benchmarks_docker.ps1` to run analyzer, tests, benchmarks, and optionally export results to the wiki.
- New wiki page `Benchmarks.md` with tabular results; `benchmark/render_results.dart` renders Markdown and `benchmark/export_to_wiki.dart` copies it to your wiki folder.
- Improved uploads API ergonomics with `withBinaryBody` and `withBodyStream` for non-multipart uploads.

Docs:

- Updated README and wiki (Getting Started, Uploads, Decoding, Cookbook) to reflect `withX` naming.
- README examples show `.withMethod(HttpMethod.get)` and `.withApiVersion('v2')` patterns.

Internal/Tooling:

- Dockerfile and .dockerignore added for consistent CI/repeatable runs.
- Minor analyzer cleanups; tests remain green.

## 1.1.0 - 2025-10-12

New: Per-request API Versioning with placeholders and custom resolvers

- Per-request API version switching via `SonicRequestBuilder.useApiVersion('v2')`.
- `BaseConfiguration.apiVersions` supports placeholders:
  `{baseUrl}`, `{origin}`, `{scheme}`, `{host}`, `{port}`, `{basePath}`, `{version}`.
- Custom placeholder resolver: `apiVersionPlaceholderResolver(name, arg, baseUri, version)`.
- Optional environment-based resolution for `{env:NAME}` (disabled by default):
  - `envPlaceholdersFromDartDefines`: read from `String.fromEnvironment(NAME)`.
  - `envPlaceholdersFromProcessEnv`: read from `Platform.environment[NAME]`.
- URL resolution, caching/deduplication, and rate-limiting/circuit selection honor the resolved absolute URL.
- Download path and onRequest hooks use the effective baseUrl.

Docs

- README: Feature bullet, API Versioning section with placeholders.
- Wiki: API-Versioning page with configuration, placeholders, custom resolver, env flags, and examples.

Tests

- Added tests for `{baseUrl}`, `{origin}`/`{version}`, custom resolver, and general request wiring.

Internal

- Minor lint cleanups and consistency tweaks around control bodies and import ordering.

---

## 1.0.0

Major release with a production-ready, batteries-included HTTP client on top of Dio. Highlights:

- Safe decoding helpers: DecodeResult<T>, DecodeError, safeDecoder<T>()
- Typed builder API with cached decoders per type
- Retries with backoff+jitter and Retry-After support; 429 considered retryable
- Per-host rate limiting (token bucket) with RequestPriority (low/normal/high)
- Circuit breaker per-host (Closed/Open/HalfOpen) with event hooks
- Request templates registry for reusable presets
- Caching: in-memory LRU with TTL, SWR (stale-while-revalidate), ETag/Last-Modified validation and Expires fallback; optional composite/file stores
- Request deduplication for identical in-flight GETs
- Observability: response.extra includes timers (durationMs, networkMs, decodeMs, cacheLookupMs, cacheRevalidateMs, rateLimitWaitMs), retryDelaysMs, deduplicated, and requestUrl
- Pagination utilities: RFC Link header parsing, cursor helpers, offset/limit and page adapters; Paged<T> and SonicResponse.toPaged for typed pagination
- Token refresh: SimpleAuthRefreshConfig and AuthRefreshInterceptor
- Fluent uploads with FormData helpers (upload(), field/fields, files, fileFromPath/Bytes/Stream)

Breaking changes:

- Timeout values in constants now use Duration instead of int milliseconds
- Public API surface expanded; ensure imports use `package:sonic/sonic.dart`

Docs:

- README simplified with links to GitHub Wiki, plus quick examples
- Cookbook added with pagination, templates, circuit breaker, and metrics recipes

Tooling:

- Added GitHub Actions workflows for wiki preview and link checking

## 0.0.3

- Documentation Update

## 0.0.2

- Initial version.
