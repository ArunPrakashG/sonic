# Sonic Cookbook

A collection of focused recipes showing how to use Sonic features in real apps.

## Cursor-based pagination (JSON body)

Many APIs return cursors in the JSON payload rather than RFC Link headers.

```dart
// Response shape example
// { "data": [ ... ], "meta": { "nextCursor": "abc123" } }

final sonic = Sonic.initialize(
  baseConfiguration: const BaseConfiguration(baseUrl: 'https://api.example.com'),
);

// First page
final res = await sonic
    .create<Map<String, dynamic>>(url: '/posts')
    .withDecoder((j) => j as Map<String, dynamic>)
    .execute();

// Build next with the cursor
final next = res.nextCursor(sonic, cursorPath: 'meta.nextCursor', param: 'cursor');
final res2 = await next?.execute();

// Or use pluck/envelope if you need to decode into models first
```

## Offset/limit and page-number pagination

```dart
final base = 'https://api.example.com/items?limit=20&offset=0';
final nextUrl = advanceOffsetLimit(url: base, pageSize: 20);
final prevUrl = advanceOffsetLimit(url: nextUrl, pageSize: 20, next: false);

final pageBase = 'https://api.example.com/items?page=1';
final page2 = advancePageNumber(url: pageBase);
final page1 = advancePageNumber(url: page2, next: false);
```

## Typed pagination with toPaged and makePaged

When your API returns a list of items and either provides cursors in the body or RFC Link headers, you can build a strongly-typed page easily.

```dart
class Post {
  final int id;
  final String title;
  Post({required this.id, required this.title});
  factory Post.fromJson(Map<String, dynamic> j) =>
      Post(id: j['id'] as int, title: j['title'] as String);
}

final res = await sonic
    .create<Map<String, dynamic>>(url: '/posts?limit=10')
    .withDecoder((j) => j as Map<String, dynamic>)
    .execute();

// If your items live under data[] and the next cursor is at meta.nextCursor
final paged = res.toPaged<Post>(
  itemDecoder: (j) => Post.fromJson(j as Map<String, dynamic>),
  itemsPath: 'data',
  nextCursorPath: 'meta.nextCursor',
  prevCursorPath: 'meta.prevCursor',
  cursorParam: 'cursor',
);

// Current page items
for (final p in paged.items) {
  print('${p.id}: ${p.title}');
}

// Next/Prev page references (if available)
final nextRef = paged.next; // has .url and a list decoder
if (nextRef != null) {
  // You can fire the next request using Sonic
  final nextRes = await sonic
      .create<List<Map<String, dynamic>>>(url: nextRef.url)
      .withDecoder(nextRef.decoder)
      .execute();

  // nextRes.data is List<Post> after mapping in decoder
}

// Alternatively, if you already have raw body/headers, use makePaged directly
final paged2 = makePaged<Post>(
  body: res.data,
  headers: res.headers,
  requestUrl: res.extra?['requestUrl'] as String?,
  itemDecoder: (j) => Post.fromJson(j as Map<String, dynamic>),
  itemsPath: 'data',
  nextCursorPath: 'meta.nextCursor',
  prevCursorPath: 'meta.prevCursor',
);
```

## Circuit breaker scenarios and custom events

```dart
final sonic = Sonic.initialize(
  baseConfiguration: BaseConfiguration(
    baseUrl: 'https://api.example.com',
    circuitBreakerConfig: const CircuitBreakerConfig(
      failureThreshold: 5,
      coolDown: Duration(seconds: 30),
    ),
    onCircuitEvent: (host, state) {
      // Hook into analytics/logger
      print('Circuit($host) -> $state');
    },
  ),
);

// On repeated failures (>= failureThreshold), breaker opens and fails fast until coolDown.
// After coolDown, one or more half-open trial requests are allowed; on success, circuit closes.
```

See also: [Circuit Breaker wiki](wiki/Circuit-Breaker.md)

## Templates with dynamic token providers

```dart
String? token;
Future<String> refreshToken() async {
  // fetch/refresh token and return it
  token = 'new_access_token';
  return token!;
}

final sonic = Sonic.initialize(
  baseConfiguration: BaseConfiguration(
    baseUrl: 'https://api.example.com',
    authRefresh: SimpleAuthRefreshConfig(
      shouldRefresh: (err) => err.response?.statusCode == 401,
      refresh: refreshToken,
      setAuthHeader: (req, t) => req.headers['Authorization'] = 'Bearer $t',
    ),
  ),
);

sonic.registerTemplate('authJson', (b) {
  b.withHeader('Content-Type', 'application/json');
  if (token != null) {
    b.withBearerToken(token!);
  }
});

final builder = sonic
    .template<Map<String, dynamic>>('authJson', url: '/secure')
    .withDecoder((j) => j as Map<String, dynamic>);
```

## Interpreting stage timers for performance tuning

`SonicResponse.extra` includes:

- durationMs: overall E2E time
- cacheLookupMs: cache lookup time (if cache enabled)
- cacheRevalidateMs: time for SWR background validation (may be null)
- networkMs: time for network call execution
- rateLimitWaitMs: backpressure delay imposed by limiter
- decodeMs: time to decode payload

Tips:

- High rateLimitWaitMs → increase permits or mark request high priority.
- High networkMs → check server latency, reduce payload size, or enable gzip.
- Frequent cacheRevalidateMs → consider longer TTL or altering Cache-Control.
- High decodeMs → optimize decoders or reduce pluck/envelope work.

## Retry policies and idempotency keys

When calling non-idempotent endpoints (e.g., POST), keep retries disabled by default or use an idempotency key on the server and client:

```dart
final res = await sonic
  .create<Map<String, dynamic>>(url: '/payments')
  .post()
  .withIdempotencyKey() // generate a unique key
  .withRetryOptions(const RetryOptions(maxAttempts: 1)) // disable automatic retries
  .execute();
```

If your backend supports idempotent POST with the key, you can opt-in to retries for POST:

```dart
final retryPost = const RetryOptions(
  maxAttempts: 3,
  retryMethods: {'GET','HEAD','PUT','DELETE','OPTIONS','POST'},
);

final res2 = await sonic
  .create<Map<String, dynamic>>(url: '/payments')
  .post()
  .withIdempotencyKey('payment-123')
  .withRetryOptions(retryPost)
  .execute();
```

## Cache stores (File/Composite) and SWR tips

```dart
final store = CompositeCacheStore(
  memory: InMemoryCacheStore(maxEntries: 512),
  file: FileCacheStore(directoryPath: './.sonic-cache', maxEntries: 2048),
);

final sonic = Sonic.initialize(
  baseConfiguration: BaseConfiguration(
    baseUrl: 'https://api.example.com',
    cacheStore: store,
    cachePolicy: const CachePolicy(
      enabled: true,
      ttl: Duration(minutes: 5),
      staleWhileRevalidate: Duration(minutes: 15),
    ),
  ),
);

// Enable cache per request (GET). SWR revalidates in background when stale.
final res = await sonic
  .create<List<dynamic>>(url: '/items')
  .withDecoder((j) => j as List<dynamic>)
  .cache()
  .execute();

// If you pluck a nested value for GET, cache is automatically disabled to avoid mixing shapes.
final res2 = await sonic
  .create<Map<String, dynamic>>(url: '/feed')
  .pluck('data.items')
  .withDecoder((j) => j as List<dynamic>)
  .cache() // no-op when pluck is set for GET
  .execute();
```

See also:

- [Caching wiki](wiki/Caching.md)
- [Rate Limiting wiki](wiki/Rate-Limiting.md)
