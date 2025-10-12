# Release Notes - Sonic v1.3.0

**Release Date**: October 12, 2025

## 🎯 Overview

Version 1.3.0 introduces a powerful interface-based auth refresh system that allows developers to implement custom authentication logic while maintaining full backward compatibility with existing code.

## ✨ What's New

### Interface-Based Auth Refresh

The auth refresh system has been refactored from a callback-based approach to an interface-based design, enabling:

- **Custom implementations** via `IAuthRefreshHandler` interface
- **Full control** over refresh logic, token storage, and error handling
- **Better testability** with mockable interfaces
- **Type safety** with compile-time guarantees
- **Backward compatibility** - existing `SimpleAuthRefreshConfig` usage unchanged

### New Components

#### `IAuthRefreshHandler` Interface

Implement this interface for custom auth refresh behavior:

```dart
class MyAuthHandler implements IAuthRefreshHandler {
  @override
  bool shouldRefresh(DioException err) {
    return err.response?.statusCode == 401;
  }

  @override
  Future<String> refreshToken() async {
    // Your refresh logic
    return newToken;
  }

  @override
  void setAuthHeader(RequestOptions req, String accessToken) {
    req.headers['Authorization'] = 'Bearer $accessToken';
  }

  @override
  void onRefreshSuccess(String newToken) {
    // Save to secure storage, log, etc.
  }

  @override
  void onRefreshError(dynamic error) {
    // Handle failure, logout user, etc.
  }
}
```

#### `DefaultAuthRefreshHandler`

Default implementation using callback functions:

```dart
AuthRefreshInterceptor(
  handler: DefaultAuthRefreshHandler(
    shouldRefresh: (err) => err.response?.statusCode == 401,
    refresh: () async => await authService.refreshToken(),
    setAuthHeader: (req, token) => req.headers['Authorization'] = 'Bearer $token',
    onSuccess: (token) => storage.save(token),
    onError: (error) => authService.logout(),
  ),
)
```

#### Enhanced `SimpleAuthRefreshConfig`

Added lifecycle hooks while maintaining backward compatibility:

```dart
SimpleAuthRefreshConfig(
  shouldRefresh: (err) => err.response?.statusCode == 401,
  refresh: () async => await authService.refreshToken(),
  setAuthHeader: (req, token) => req.headers['Authorization'] = 'Bearer $token',
  onSuccess: (token) => storage.save(token),  // NEW!
  onError: (error) => authService.logout(),   // NEW!
)
```

## 🔄 Migration Guide

### No Changes Needed

If you use `SimpleAuthRefreshConfig` in `BaseConfiguration`, **no changes are required**:

```dart
// This continues to work exactly as before
final sonic = Sonic.initialize(
  baseConfiguration: BaseConfiguration(
    baseUrl: 'https://api.example.com',
    authRefresh: SimpleAuthRefreshConfig(
      shouldRefresh: (err) => err.response?.statusCode == 401,
      refresh: () async => await refreshToken(),
      setAuthHeader: (req, token) => req.headers['Authorization'] = 'Bearer $token',
    ),
  ),
);
```

### Manual `AuthRefreshInterceptor` Usage (Rare)

If you manually create `AuthRefreshInterceptor` instances, wrap callbacks in `DefaultAuthRefreshHandler`:

**Before:**
```dart
sonic.addInterceptor(AuthRefreshInterceptor(
  shouldRefresh: (err) => err.response?.statusCode == 401,
  refresh: () async => token,
  setAuthHeader: (req, token) => req.headers['Authorization'] = 'Bearer $token',
));
```

**After:**
```dart
sonic.addInterceptor(AuthRefreshInterceptor(
  handler: DefaultAuthRefreshHandler(
    shouldRefresh: (err) => err.response?.statusCode == 401,
    refresh: () async => token,
    setAuthHeader: (req, token) => req.headers['Authorization'] = 'Bearer $token',
  ),
));
```

## 📚 Examples

### Basic Custom Handler

See `example/custom_auth_handler_example.dart` for a complete example demonstrating:
- Custom handler implementation
- SimpleAuthRefreshConfig usage
- DefaultAuthRefreshHandler usage

### Production-Ready Handler

See `example/production_auth_handler_example.dart` for an enterprise-grade implementation with:
- ✅ Retry logic with exponential backoff
- ✅ Token persistence to secure storage
- ✅ Refresh loop prevention
- ✅ Automatic logout on permanent failure
- ✅ Refresh token rotation support
- ✅ Comprehensive logging

## 🧪 Testing

All 71 tests pass successfully:
```bash
dart test -r compact
00:13 +71: All tests passed!
```

## 📖 Documentation

- **Wiki**: Updated `AuthRefresh.md` with comprehensive examples
- **Migration Guide**: `AUTH_REFACTORING.md` with detailed migration steps
- **Examples**: Two new example files demonstrating usage patterns

## 🎁 Benefits

| Feature | Benefit |
|---------|---------|
| Interface-based | Implement custom logic with full control |
| Type safe | Compiler-enforced contracts |
| Testable | Easy to mock in unit tests |
| Extensible | Add features like retry, persistence, logging |
| Backward compatible | Existing code works unchanged |
| Lifecycle hooks | React to success/failure events |

## 🚀 Upgrade Instructions

1. Update your `pubspec.yaml`:
   ```yaml
   dependencies:
     sonic: ^1.3.0
   ```

2. Run:
   ```bash
   dart pub upgrade sonic
   ```

3. If you use `SimpleAuthRefreshConfig`, no code changes needed!

4. If you manually create `AuthRefreshInterceptor`, see migration guide above.

## 📦 Package Info

- **Version**: 1.3.0
- **Pub.dev**: https://pub.dev/packages/sonic
- **Repository**: https://github.com/ArunPrakashG/sonic
- **Documentation**: https://github.com/ArunPrakashG/sonic/wiki

## 🙏 Credits

Thanks to all contributors and users who provided feedback to make Sonic better!

---

**Full Changelog**: See [CHANGELOG.md](CHANGELOG.md) for complete details.
