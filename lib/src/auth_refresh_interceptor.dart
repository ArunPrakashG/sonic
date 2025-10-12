import 'dart:async';

import 'package:dio/dio.dart';

/// A helper interceptor to handle 401 responses by refreshing tokens and retrying.
///
/// Usage:
///   sonic.addInterceptor(AuthRefreshInterceptor(
///     shouldRefresh: (err) => err.response?.statusCode == 401,
///     refresh: () async {
///       // perform refresh here and return new access token
///     },
///     setAuthHeader: (req, token) => req.headers['Authorization'] = 'Bearer $token',
///   ));
class AuthRefreshInterceptor extends Interceptor {
  AuthRefreshInterceptor({
    required this.shouldRefresh,
    required this.refresh,
    required this.setAuthHeader,
  });

  final bool Function(DioException err) shouldRefresh;
  final Future<String> Function() refresh;
  final void Function(RequestOptions req, String accessToken) setAuthHeader;

  String? _token;
  Future<void>? _refreshing;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_token != null) {
      setAuthHeader(options, _token!);
    }
    super.onRequest(options, handler);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (!shouldRefresh(err)) {
      return handler.next(err);
    }

    // Ensure only one refresh is in-flight
    _refreshing ??= _doRefresh();
    try {
      await _refreshing;
    } finally {
      _refreshing = null;
    }

    // Retry the original request with the new token
    final req = err.requestOptions;
    if (_token != null) {
      setAuthHeader(req, _token!);
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
    _token = await refresh();
  }
}

class SimpleAuthRefreshConfig {
  const SimpleAuthRefreshConfig({
    required this.shouldRefresh,
    required this.refresh,
    required this.setAuthHeader,
  });

  final bool Function(DioException err) shouldRefresh;
  final Future<String> Function() refresh;
  final void Function(RequestOptions req, String accessToken) setAuthHeader;
}
