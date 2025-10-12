import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

void main() {
  test('Templates API compiles and applies', () async {
    final sonic = Sonic.initialize(
        baseConfiguration:
            const BaseConfiguration(baseUrl: 'https://example.com'));
    sonic.registerTemplate('authJsonPost', (b) {
      b.post().withHeader('Content-Type', 'application/json');
    });
    final builder = sonic
        .template<String>('authJsonPost', url: '/demo')
        .withDecoder((j) => 'ok');
    expect(builder, isA<SonicRequestBuilder<String>>());
  });
}
