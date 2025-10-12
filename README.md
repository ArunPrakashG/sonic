<h1 align="center">⚡ Sonic</h1>
<p align="center">
  An HTTP Client with a fluent interface and improved type support.
</p>
<p align="center">
  <a href="https://pub.dev/packages/sonic"><img src="https://img.shields.io/pub/v/sonic?label=pub.dev&color=%23009dff" alt="pub version" /></a>
  <a href="https://pub.dev/packages/sonic/score"><img src="https://img.shields.io/pub/points/sonic?logo=dart&logoColor=white" alt="pub points" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-brightgreen" alt="license MIT" /></a>
  <a href="https://pub.dev/documentation/sonic/latest/"><img src="https://img.shields.io/badge/api-reference-pub.dev-blue" alt="API Reference" /></a>
</p>
<p align="center"><i>Blazingly simple, production-ready networking on top of Dio — with smart caching, retries, dedup, and observability.</i></p>

---

## ✨ Features

- ✨ Fluent interface and typed decoders (cached per type)
- 🔁 Retries with backoff, jitter, and Retry-After; 429-aware
- 🧠 Caching: in-memory TTL+LRU, SWR, ETag/Last-Modified/Expires
- 🤝 Request deduplication for identical in-flight GETs
- 🧑‍💻 Per-host rate limiting (token bucket) with priority
- 🛡️ Circuit breaker per host with event hooks
- 🧩 Templates for reusable request presets
- 📊 Observability: detailed response.extra metrics
 - 📤 Fluent uploads (multipart, fields/files)
- 📄 Pagination utilities (Link headers, cursors, adapters, Paged<T>)

<!-- Keeping core bullets concise; details covered in sections below. -->

## 📦 Install

Use your preferred tool:

```sh
# Dart
dart pub add sonic

# Flutter
flutter pub add sonic
```

## 🚀 Getting Started

See the Quickstart in the Wiki: [Getting Started](https://github.com/ArunPrakashG/sonic/wiki/Getting-Started)

## 🔧 Usage

See examples and patterns in the Wiki pages linked below.

##  Wiki

The main README is intentionally minimal. Full docs live in the GitHub Wiki:

- 📘 [Getting Started](https://github.com/ArunPrakashG/sonic/wiki/Getting-Started)
- 🗃️ [Caching](https://github.com/ArunPrakashG/sonic/wiki/Caching)
- 🔁 [Retries](https://github.com/ArunPrakashG/sonic/wiki/Retries)
- 🤝 [Deduplication](https://github.com/ArunPrakashG/sonic/wiki/Deduplication)
- 🔎 [Observability](https://github.com/ArunPrakashG/sonic/wiki/Observability)
- 🔐 [Auth Refresh](https://github.com/ArunPrakashG/sonic/wiki/AuthRefresh)
- 📤 [Uploads](https://github.com/ArunPrakashG/sonic/wiki/Uploads)
- 📊 [Response Metrics](https://github.com/ArunPrakashG/sonic/wiki/Metrics)
- ❓ [FAQ](https://github.com/ArunPrakashG/sonic/wiki/FAQ)
- 📚 [Cookbook](https://github.com/ArunPrakashG/sonic/wiki/Cookbook)
  - Or see the local [COOKBOOK.md](COOKBOOK.md) for quick-start recipes.
  - [Circuit breaker probe/events](https://github.com/ArunPrakashG/sonic/wiki/Circuit-Breaker)
  - [Rate limiter with priority](https://github.com/ArunPrakashG/sonic/wiki/Rate-Limiting)
  - [Retry with idempotency keys](https://github.com/ArunPrakashG/sonic/wiki/Retries#idempotency-keys)
  - [Cache stores & SWR](https://github.com/ArunPrakashG/sonic/wiki/Caching#stores-and-swr)

### 📄 Pagination (Link headers)

If your API returns RFC Link headers, you can build next/prev requests directly from a response:

```dart
final res = await sonic.create<List<Post>>(url: '/posts')
  .withDecoder((j) => (j as List).map((e) => Post.fromJson(e)).toList())
  .execute();

final next = res.nextPage(sonic);
final res2 = await next?.withDecoder((j) => (j as List).map((e) => Post.fromJson(e)).toList()).execute();
```

For cursor in JSON body instead of headers, you can still use `pluck()`/`envelope()` and construct URLs yourself.

Or, build a strongly-typed page using toPaged/makePaged:

```dart
final res = await sonic
    .create<Map<String, dynamic>>(url: '/posts?limit=10')
    .execute();

final paged = res.toPaged<Post>(
  itemDecoder: (j) => Post.fromJson(j as Map<String, dynamic>),
  itemsPath: 'data',
  nextCursorPath: 'meta.nextCursor',
  prevCursorPath: 'meta.prevCursor',
  cursorParam: 'cursor',
);

for (final item in paged.items) {
  // ...
}

final nextRef = paged.next; // has url and a list decoder
```

### 🛡️ Circuit breaker events

Provide an event hook via BaseConfiguration to observe state changes per host:

```dart
final sonic = Sonic.initialize(
  baseConfiguration: BaseConfiguration(
    baseUrl: 'https://api.example.com',
    circuitBreakerConfig: const CircuitBreakerConfig(failureThreshold: 5),
    onCircuitEvent: (host, state) {
      print('Circuit for $host => $state');
    },
  ),
);
```

### 🧩 Templates to reduce repetition

```dart
sonic.registerTemplate('authJsonPost', (b) {
  b.post().withHeader('Content-Type','application/json');
});

final builder = sonic.template<User>('authJsonPost', url: '/users')
  .withDecoder((j) => User.fromJson(j));
```

### ⏱️ Stage timers (response.extra)

`SonicResponse.extra` includes useful timing data when available:

- durationMs: total end-to-end time for the request
- cacheLookupMs: time spent checking cache
- cacheRevalidateMs: background revalidation time (SWR)
- networkMs: time for the network call
- rateLimitWaitMs: time spent waiting on rate limiter
- decodeMs: time to decode payload

### Rate limiting and priority

Configure per-host rate limits via BaseConfiguration:

```dart
final sonic = Sonic.initialize(
  baseConfiguration: BaseConfiguration(
    baseUrl: 'https://api.example.com',
    rateLimits: {
      'api.example.com': const RateLimitConfig(permitsPerSecond: 10, burst: 20),
    },
  ),
);

// Mark important requests as high priority to reduce wait time under backpressure
final res = await sonic
    .create<String>(url: '/data')
    .withPriority(RequestPriority.high)
    .execute();
```

HTTP 429 responses are considered retryable by default and Sonic respects the Retry-After header when computing backoff.

## 📊 Response metrics

📊 Every `SonicResponse` includes optional `extra` metadata to help with diagnostics and tuning:

- ⏱️ durationMs: total wall time for the request path (including cache checks)
- 🗃️ cache: one of `network`, `store`, or `validated-304`
- 🏷️ cacheEvent: `network`, `hit`, `stale`, or `validated`
- 🔁 retries: number of retry attempts performed
- ⌛ retryDelaysMs: list of delays applied between attempts
- 🤝 deduplicated: whether this response came from a deduplicated in-flight GET

## 📝 Notes

- 🧪 You can also get raw response and ignore the type parsing by using `asRawRequest()` builder method and specifying the type parameter as `dynamic`
- 🧠 You wont need to pass decoder using `withDecoder` after the first call to the same type as the decoder will be cached based on the type.
- 🌐 You can either pass relative url (path) or an absolute url to the `url` named parameter.
- 🐞 If `debugMode` is true, `LogInterceptor` will be added to the internal `Dio` instance and it will be used to log everything related to a network call in the standard output.
- 🧩 You can have multiple instances of `Sonic` as individually, they do not share resources with each other. But it is recommended to have a global instance of `Sonic` and use dependency injection to inject them into your business logic.
- 📦 You can use `FormData` as body for uploading files etc. You can wrap the file with `MultipartFile` instance. these are from `Dio` library.

## 🧪 Example

🔍 Check a runnable example in `example/sonic_example.dart`.

## 📄 License

📄 MIT © [Arun Prakash](https://github.com/ArunPrakashG). See [`LICENSE`](LICENSE).

## 🙌 Contributions

🙌 Contributions are always welcome!
