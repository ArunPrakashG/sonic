// ignore_for_file: avoid_print, unused_local_variable

import 'package:sonic/sonic.dart';

/// Custom authentication handler with persistent token storage and logging.
class CustomAuthHandler implements IAuthRefreshHandler {
  CustomAuthHandler({
    required this.authService,
    required this.storage,
  });

  final AuthService authService;
  final TokenStorage storage;

  @override
  bool shouldRefresh(DioException err) {
    // Refresh on 401 Unauthorized
    return err.response?.statusCode == 401;
  }

  @override
  Future<String> refreshToken() async {
    print('[Auth] Refreshing token...');

    try {
      final newToken = await authService.refreshAccessToken();
      return newToken;
    } catch (e) {
      print('[Auth] Refresh failed: $e');
      rethrow;
    }
  }

  @override
  void setAuthHeader(RequestOptions req, String accessToken) {
    req.headers['Authorization'] = 'Bearer $accessToken';
    print('[Auth] Set token: ${accessToken.substring(0, 10)}...');
  }

  @override
  void onRefreshSuccess(String newToken) {
    print('[Auth] Refresh successful!');
    // Save new token to persistent storage
    storage.saveToken(newToken);
  }

  @override
  void onRefreshError(dynamic error) {
    print('[Auth] Refresh failed - logging out user');
    // Handle refresh failure (e.g., redirect to login)
    authService.logout();
  }
}

/// Mock authentication service
class AuthService {
  String? _refreshToken = 'refresh_token_123';

  Future<String> refreshAccessToken() async {
    if (_refreshToken == null) {
      throw Exception('No refresh token available');
    }

    // Simulate API call
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Return new access token
    return 'new_access_token_${DateTime.now().millisecondsSinceEpoch}';
  }

  void logout() {
    _refreshToken = null;
    print('[Auth] User logged out');
  }
}

/// Mock token storage
class TokenStorage {
  String? _token;

  void saveToken(String token) {
    _token = token;
    print('[Storage] Token saved');
  }

  String? getToken() => _token;
}

void main() async {
  // Initialize dependencies
  final authService = AuthService();
  final storage = TokenStorage();

  // Create custom auth handler
  final authHandler = CustomAuthHandler(
    authService: authService,
    storage: storage,
  );

  // Initialize Sonic with custom handler
  final sonic = Sonic.initialize(
    baseConfiguration: const BaseConfiguration(
      baseUrl: 'https://api.example.com',
    ),
  );

  // Add the auth interceptor with custom handler
  sonic.addInterceptor(AuthRefreshInterceptor(
    handler: authHandler,
  ));

  print('✅ Sonic initialized with custom auth handler!\n');

  // Alternative: Using SimpleAuthRefreshConfig (still works)
  final sonicSimple = Sonic.initialize(
    baseConfiguration: BaseConfiguration(
      baseUrl: 'https://api.example.com',
      authRefresh: SimpleAuthRefreshConfig(
        shouldRefresh: (err) => err.response?.statusCode == 401,
        refresh: () async => authService.refreshAccessToken(),
        setAuthHeader: (req, token) {
          req.headers['Authorization'] = 'Bearer $token';
        },
        onSuccess: storage.saveToken,
        onError: (error) => authService.logout(),
      ),
    ),
  );

  print('✅ Sonic initialized with SimpleAuthRefreshConfig!\n');

  // Using DefaultAuthRefreshHandler directly
  final sonicDefault = Sonic.initialize(
    baseConfiguration: const BaseConfiguration(
      baseUrl: 'https://api.example.com',
    ),
  );

  sonicDefault.addInterceptor(
    AuthRefreshInterceptor(
      handler: DefaultAuthRefreshHandler(
        shouldRefresh: (err) => err.response?.statusCode == 401,
        refresh: () async => authService.refreshAccessToken(),
        setAuthHeader: (req, token) {
          req.headers['Authorization'] = 'Bearer $token';
        },
        onSuccess: (token) {
          print('[Callback] Token refreshed successfully!');
          storage.saveToken(token);
        },
        onError: (error) {
          print('[Callback] Refresh failed: $error');
          authService.logout();
        },
      ),
    ),
  );

  print('✅ Sonic initialized with DefaultAuthRefreshHandler!\n');
  print('All three approaches work correctly! 🎉');
}
