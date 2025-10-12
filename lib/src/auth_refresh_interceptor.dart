import 'dart:async';

import 'package:dio/dio.dart';

/// Interface for handling authentication token refresh logic.
///
/// Implement this interface to provide custom refresh behavior.
///
/// Example:
/// ```dart
/// class MyAuthHandler implements IAuthRefreshHandler {
///   @override
///   bool shouldRefresh(DioException err) {
///     return err.response?.statusCode == 401;
///   }
///
///   @override
///   Future<String> refreshToken() async {
///     final response = await myAuthService.refresh();
///     return response.accessToken;
///   }
///
///   @override
///   void setAuthHeader(RequestOptions req, String accessToken) {
///     req.headers['Authorization'] = 'Bearer $accessToken';
///   }
///
///   @override
///   void onRefreshSuccess(String newToken) {
///     // Optional: save token to storage
///     secureStorage.write('access_token', newToken);
///   }
///
///   @override
///   void onRefreshError(dynamic error) {
///     // Optional: handle refresh failure (e.g., logout user)
///     authService.logout();
///   }
/// }
/// ```
abstract class IAuthRefreshHandler {
  /// Determines if the error should trigger a token refresh.
  ///
  /// Typically checks for 401 Unauthorized responses.
  bool shouldRefresh(DioException err);

  /// Performs the token refresh operation.
  ///
  /// Should return the new access token or throw an error if refresh fails.
  Future<String> refreshToken();

  /// Sets the authorization header on the request using the provided token.
  ///
  /// Common implementations include Bearer tokens, API keys, etc.
  void setAuthHeader(RequestOptions req, String accessToken);

  /// Called after a successful token refresh.
  ///
  /// Override to perform actions like saving the token to storage.
  void onRefreshSuccess(String newToken) {}

  /// Called when token refresh fails.
  ///
  /// Override to perform actions like logging out the user.
  void onRefreshError(dynamic error) {}
}

/// Default implementation of [IAuthRefreshHandler] using callback functions.
///
/// This provides a simple way to configure auth refresh without creating
/// a custom class.
class DefaultAuthRefreshHandler implements IAuthRefreshHandler {
  DefaultAuthRefreshHandler({
    required bool Function(DioException err) shouldRefresh,
    required Future<String> Function() refresh,
    required void Function(RequestOptions req, String accessToken)
        setAuthHeader,
    void Function(String newToken)? onSuccess,
    void Function(dynamic error)? onError,
  })  : _shouldRefresh = shouldRefresh,
        _refresh = refresh,
        _setAuthHeader = setAuthHeader,
        _onSuccess = onSuccess,
        _onError = onError;

  final bool Function(DioException err) _shouldRefresh;
  final Future<String> Function() _refresh;
  final void Function(RequestOptions req, String accessToken) _setAuthHeader;
  final void Function(String newToken)? _onSuccess;
  final void Function(dynamic error)? _onError;

  @override
  bool shouldRefresh(DioException err) => _shouldRefresh(err);

  @override
  Future<String> refreshToken() => _refresh();

  @override
  void setAuthHeader(RequestOptions req, String accessToken) =>
      _setAuthHeader(req, accessToken);

  @override
  void onRefreshSuccess(String newToken) => _onSuccess?.call(newToken);

  @override
  void onRefreshError(dynamic error) => _onError?.call(error);
}

/// A helper interceptor to handle 401 responses by refreshing tokens and retrying.
///
/// Usage with custom handler:
/// ```dart
/// class MyAuthHandler implements IAuthRefreshHandler {
///   // ... implement interface methods
/// }
///
/// sonic.addInterceptor(AuthRefreshInterceptor(
///   handler: MyAuthHandler(),
/// ));
/// ```
///
/// Usage with default handler:
/// ```dart
/// sonic.addInterceptor(AuthRefreshInterceptor(
///   handler: DefaultAuthRefreshHandler(
///     shouldRefresh: (err) => err.response?.statusCode == 401,
///     refresh: () async => await myAuthService.refreshToken(),
///     setAuthHeader: (req, token) => req.headers['Authorization'] = 'Bearer $token',
///   ),
/// ));
/// ```
class AuthRefreshInterceptor extends Interceptor {
  AuthRefreshInterceptor({
    required this.handler,
  });

  /// The auth refresh handler implementation.
  final IAuthRefreshHandler handler;

  String? _token;
  Future<void>? _refreshing;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_token != null) {
      this.handler.setAuthHeader(options, _token!);
    }
    super.onRequest(options, handler);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (!this.handler.shouldRefresh(err)) {
      return handler.next(err);
    }

    // Ensure only one refresh is in-flight
    _refreshing ??= _doRefresh();
    try {
      await _refreshing;
    } on Exception catch (e) {
      this.handler.onRefreshError(e);
      return handler.next(err);
    } finally {
      _refreshing = null;
    }

    // Retry the original request with the new token
    final req = err.requestOptions;
    if (_token != null) {
      this.handler.setAuthHeader(req, _token!);
    }

    final dio = err.requestOptions.extra['dio'] as Dio?;
    if (dio == null) {
      return handler.next(err);
    }
    try {
      final result = await dio.fetch(req);
      return handler.resolve(result);
    } catch (_) {
      return handler.next(err);
    }
  }

  Future<void> _doRefresh() async {
    _token = await handler.refreshToken();
    handler.onRefreshSuccess(_token!);
  }
}

/// Simple configuration for auth refresh using callback functions.
///
/// This is a convenience wrapper around [DefaultAuthRefreshHandler].
/// For more control, implement [IAuthRefreshHandler] directly.
///
/// Example:
/// ```dart
/// SimpleAuthRefreshConfig(
///   shouldRefresh: (err) => err.response?.statusCode == 401,
///   refresh: () async {
///     final token = await authService.refreshToken();
///     return token;
///   },
///   setAuthHeader: (req, token) {
///     req.headers['Authorization'] = 'Bearer $token';
///   },
///   onSuccess: (token) => storage.saveToken(token),
///   onError: (error) => authService.logout(),
/// )
/// ```
class SimpleAuthRefreshConfig {
  const SimpleAuthRefreshConfig({
    required this.shouldRefresh,
    required this.refresh,
    required this.setAuthHeader,
    this.onSuccess,
    this.onError,
  });

  final bool Function(DioException err) shouldRefresh;
  final Future<String> Function() refresh;
  final void Function(RequestOptions req, String accessToken) setAuthHeader;
  final void Function(String newToken)? onSuccess;
  final void Function(dynamic error)? onError;

  /// Converts this config to an [IAuthRefreshHandler] implementation.
  IAuthRefreshHandler toHandler() {
    return DefaultAuthRefreshHandler(
      shouldRefresh: shouldRefresh,
      refresh: refresh,
      setAuthHeader: setAuthHeader,
      onSuccess: onSuccess,
      onError: onError,
    );
  }
}
