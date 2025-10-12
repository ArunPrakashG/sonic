import 'package:dio/dio.dart';
import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

void main() {
  group('API version switching', () {
    test('defaults to baseUrl when no version set', () async {
      final seen = <String?>[];
      final sonic = Sonic(
        baseConfiguration: BaseConfiguration(
          baseUrl: 'https://api.example.com/base',
          onRequest: (opts) => seen.add(opts.baseUrl),
        ),
      );
      sonic.initialize(client: Dio(BaseOptions()));

      // Use httpbin.org absolute URL to avoid real call; intercept with Dio adapter? Instead, expect failure but onRequest fired.
      try {
        await sonic.create<Map<String, dynamic>>(url: '/users').get().execute();
      } catch (_) {}

      // We only assert that onRequest captured correct baseUrl value
      expect(seen.isNotEmpty, true);
      expect(seen.first, 'https://api.example.com/base');
    });

    test('uses mapped version when provided', () async {
      final seen = <String?>[];
      final sonic = Sonic(
        baseConfiguration: BaseConfiguration(
          baseUrl: 'https://api.example.com/base',
          apiVersions: const {
            'v1': 'https://api.example.com/v1',
            'v2': 'https://api.example.com/v2',
          },
          onRequest: (opts) => seen.add(opts.baseUrl),
        ),
      );
      sonic.initialize(client: Dio(BaseOptions()));

      try {
        await sonic
            .create<Map<String, dynamic>>(url: '/users')
            .useApiVersion('v2')
            .get()
            .execute();
      } catch (_) {}

      expect(seen.isNotEmpty, true);
      expect(seen.first, 'https://api.example.com/v2');
    });

    test('falls back to default when unknown version key', () async {
      final seen = <String?>[];
      final sonic = Sonic(
        baseConfiguration: BaseConfiguration(
          baseUrl: 'https://api.example.com/base',
          apiVersions: const {
            'v1': 'https://api.example.com/v1',
          },
          onRequest: (opts) => seen.add(opts.baseUrl),
        ),
      );
      sonic.initialize(client: Dio(BaseOptions()));

      try {
        await sonic
            .create<String>(url: '/ping')
            .useApiVersion('v3')
            .get()
            .execute();
      } catch (_) {}

      expect(seen.isNotEmpty, true);
      expect(seen.first, 'https://api.example.com/base');
    });

    test('supports {baseUrl} placeholder replacement', () async {
      final seen = <String?>[];
      final sonic = Sonic(
        baseConfiguration: BaseConfiguration(
          baseUrl: 'https://api.example.com',
          apiVersions: const {
            'v2': '{baseUrl}/v2',
          },
          onRequest: (opts) => seen.add(opts.baseUrl),
        ),
      );
      sonic.initialize(client: Dio(BaseOptions()));

      try {
        await sonic
            .create<String>(url: '/echo')
            .useApiVersion('v2')
            .get()
            .execute();
      } catch (_) {}

      expect(seen.isNotEmpty, true);
      expect(seen.first, 'https://api.example.com/v2');
    });

    test('supports {origin} and {host} and {version}', () async {
      final seen = <String?>[];
      final sonic = Sonic(
        baseConfiguration: BaseConfiguration(
          baseUrl: 'https://api.example.com/base',
          apiVersions: const {
            'v3': '{origin}/api/{version}',
          },
          onRequest: (opts) => seen.add(opts.baseUrl),
        ),
      );
      sonic.initialize(client: Dio(BaseOptions()));

      try {
        await sonic
            .create<String>(url: '/ping')
            .useApiVersion('v3')
            .get()
            .execute();
      } catch (_) {}

      expect(seen.isNotEmpty, true);
      // origin should be https://api.example.com
      expect(seen.first, 'https://api.example.com/api/v3');
    });

    test('supports custom resolver e.g. {env:REGION}', () async {
      final seen = <String?>[];
      final sonic = Sonic(
        baseConfiguration: BaseConfiguration(
          baseUrl: 'https://api.example.com',
          apiVersions: const {
            'v1': '{origin}/api/{env:REGION}',
          },
          apiVersionPlaceholderResolver: (name, arg, baseUri, version) {
            if (name == 'env' && arg == 'REGION') {
              return 'eu';
            }
            return null;
          },
          onRequest: (opts) => seen.add(opts.baseUrl),
        ),
      );
      sonic.initialize(client: Dio(BaseOptions()));

      try {
        await sonic
            .create<String>(url: '/ping')
            .useApiVersion('v1')
            .get()
            .execute();
      } catch (_) {}

      expect(seen.isNotEmpty, true);
      expect(seen.first, 'https://api.example.com/api/eu');
    });
  });
}
