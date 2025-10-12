import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

void main() {
  group('Rate limiting integration', () {
    test('Builder priority API compiles and basic flow', () async {
      // Use a dummy dio base url; we won't execute the request.
      final sonic = Sonic.initialize(
          baseConfiguration:
              const BaseConfiguration(baseUrl: 'https://example.com'));

      // Ensure we can set priority and that types are exported
      final builder = sonic
          .create<String>(url: '/x')
          .withPriority(RequestPriority.high)
          .withDecoder((j) => 'ok');

      // We will not call execute() to avoid network. Just ensure no crashes up to here.
      expect(builder, isA<SonicRequestBuilder<String>>());
    });
  });
}
