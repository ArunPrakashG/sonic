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

Minimal example:

```dart
// Create the client (initialize() is called automatically in this ctor)
final sonic = Sonic.initialize(
  baseConfiguration: const BaseConfiguration(baseUrl: 'https://api.example.com'),
);

// Typed GET with a decoder
final res = await sonic
  .create<User>(url: '/users/1')
  .withDecoder((j) => User.fromJson(j as Map<String, dynamic>))
  .execute();

if (res.isSuccess) {
  final user = res.data; // User
}
```

## Wiki

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
- 📚 [Cookbook](https://github.com/ArunPrakashG/sonic/wiki/Cookbook) — you can also use the local [COOKBOOK.md](COOKBOOK.md) for quick-start recipes.

Deep dives are available in the wiki:
- Pagination
- Circuit breaker and health probe
- Templates
- Stage timers and response metrics
- Rate limiting and priorities

<!-- Deep dive sections were moved to wiki to keep README concise. -->

## Notes

- You can bypass type parsing by using `asRawRequest()` and typing as `dynamic`.
- Decoders are cached per type; after first registration, you typically don’t need to pass them again.
- URLs can be relative (resolved against baseUrl) or absolute.
- If `debugMode` is true, a `LogInterceptor` is added to the internal Dio client to log requests/responses.
- You can have multiple `Sonic` instances, but a single shared instance via DI is recommended for most apps.
- For uploads, use multipart `FormData` and `MultipartFile` (see the Uploads wiki page).

## 🧪 Example

🔍 Check a runnable example in `example/sonic_example.dart`.

## 📄 License

📄 MIT © [Arun Prakash](https://github.com/ArunPrakashG). See [`LICENSE`](LICENSE).

## 🙌 Contributions

🙌 Contributions are always welcome!
