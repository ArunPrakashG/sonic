// ignore_for_file: avoid_print

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:sonic/sonic.dart';

/// Production-ready auth handler with retry logic, token persistence,
/// and automatic logout on refresh failure.
class ProductionAuthHandler implements IAuthRefreshHandler {
  ProductionAuthHandler({
    required this.authApiUrl,
    required this.storage,
    required this.onLogout,
    this.maxRefreshRetries = 3,
  });

  final String authApiUrl;
  final SecureTokenStorage storage;
  final VoidCallback onLogout;
  final int maxRefreshRetries;

  int _refreshAttempts = 0;
  DateTime? _lastRefreshTime;

  @override
  bool shouldRefresh(DioException err) {
    // Only refresh on 401
    if (err.response?.statusCode != 401) {
      return false;
    }

    // Prevent refresh loops - don't retry if we just refreshed
    if (_lastRefreshTime != null &&
        DateTime.now().difference(_lastRefreshTime!) <
            const Duration(seconds: 5)) {
      print('[Auth] Refresh attempted too recently, skipping');
      return false;
    }

    // Check if we have a refresh token
    if (storage.getRefreshToken() == null) {
      print('[Auth] No refresh token available');
      return false;
    }

    return true;
  }

  @override
  Future<String> refreshToken() async {
    _refreshAttempts++;
    _lastRefreshTime = DateTime.now();

    try {
      print('[Auth] Refreshing token (attempt $_refreshAttempts)...');

      final refreshToken = storage.getRefreshToken();
      if (refreshToken == null) {
        throw Exception('No refresh token available');
      }

      // Call refresh endpoint
      final dio = Dio();
      final response = await dio.post(
        authApiUrl,
        data: {
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );

      final newAccessToken = response.data['access_token'] as String?;
      final newRefreshToken = response.data['refresh_token'] as String?;

      if (newAccessToken == null) {
        throw Exception('No access token in refresh response');
      }

      // Update refresh token if provided
      if (newRefreshToken != null) {
        await storage.saveRefreshToken(newRefreshToken);
      }

      _refreshAttempts = 0; // Reset on success
      return newAccessToken;
    } catch (e) {
      print('[Auth] Refresh failed: $e');

      // Retry if under limit
      if (_refreshAttempts < maxRefreshRetries) {
        await Future<void>.delayed(Duration(seconds: _refreshAttempts));
        return refreshToken();
      }

      rethrow;
    }
  }

  @override
  void setAuthHeader(RequestOptions req, String accessToken) {
    req.headers['Authorization'] = 'Bearer $accessToken';
  }

  @override
  void onRefreshSuccess(String newToken) {
    print('[Auth] Token refresh successful');
    storage.saveAccessToken(newToken);

    // Reset failure counters
    _refreshAttempts = 0;
  }

  @override
  void onRefreshError(dynamic error) {
    print('[Auth] Token refresh failed permanently: $error');

    // Clear tokens
    storage.clearAll();

    // Logout user
    onLogout();
  }
}

/// Mock secure storage for tokens
class SecureTokenStorage {
  String? _accessToken;
  String? _refreshToken;

  Future<void> saveAccessToken(String token) async {
    _accessToken = token;
    print('[Storage] Access token saved');
  }

  Future<void> saveRefreshToken(String token) async {
    _refreshToken = token;
    print('[Storage] Refresh token saved');
  }

  String? getAccessToken() => _accessToken;
  String? getRefreshToken() => _refreshToken;

  void clearAll() {
    _accessToken = null;
    _refreshToken = null;
    print('[Storage] All tokens cleared');
  }
}

typedef VoidCallback = void Function();

void main() async {
  final storage = SecureTokenStorage();

  // Initialize with a refresh token
  await storage.saveRefreshToken('initial_refresh_token');

  final authHandler = ProductionAuthHandler(
    authApiUrl: 'https://api.example.com/auth/refresh',
    storage: storage,
    onLogout: () {
      print('[App] User logged out - redirecting to login...');
    },
  );

  final sonic = Sonic.initialize(
    baseConfiguration: const BaseConfiguration(
      baseUrl: 'https://api.example.com',
    ),
  );

  sonic.addInterceptor(AuthRefreshInterceptor(
    handler: authHandler,
  ));

  print('✅ Production auth handler initialized!\n');
  print('Features:');
  print('  - Automatic retry on refresh failure (max 3 attempts)');
  print('  - Token persistence to secure storage');
  print('  - Refresh loop prevention (5s cooldown)');
  print('  - Automatic logout on permanent failure');
  print('  - Refresh token rotation support');
}
