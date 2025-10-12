import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

void main() {
  test('registerTemplateWith + templateWith builds successfully', () async {
    final sonic = Sonic.initialize(
      baseConfiguration:
          const BaseConfiguration(baseUrl: 'https://example.com'),
    );

    sonic.registerTemplateWith<String>('tenantHeader', (b, tenant) {
      b.withHeader('X-Tenant', tenant);
    });

    final builder = sonic
        .templateWith<String, String>('tenantHeader', 'acme', url: '/foo')
        .withDecoder((_) => 'ok');

    expect(builder, isA<SonicRequestBuilder<String>>());
  });

  test('Builder.applyTemplate and applyTemplateWith chain', () async {
    final sonic = Sonic.initialize(
      baseConfiguration:
          const BaseConfiguration(baseUrl: 'https://example.com'),
    );

    sonic.registerTemplate('jsonPost', (b) {
      b.post().withHeader('Content-Type', 'application/json');
    });
    sonic.registerTemplateWith<String>('tenantHeader', (b, tenant) {
      b.withHeader('X-Tenant', tenant);
    });

    final b = sonic
        .create<void>(url: '/bar')
        .applyTemplate('jsonPost')
        .applyTemplateWith('tenantHeader', 'acme');

    // Execute against a deterministic URL; we only ensure no crash in building pipeline.
    final r = await b.asRawRequest().execute();
    expect(r.hasError || r.isSuccess, isTrue);
  });

  test('Template registry ops work', () {
    final sonic = Sonic.initialize(
      baseConfiguration:
          const BaseConfiguration(baseUrl: 'https://example.com'),
    );

    sonic.registerTemplate('a', (b) {});
    sonic.registerTemplate('b', (b) {});

    expect(sonic.hasTemplate('a'), isTrue);
    expect(sonic.hasTemplate('b'), isTrue);

    final names = sonic.listTemplates().toList();
    expect(names, containsAll(['a', 'b']));

    final removed = sonic.unregisterTemplate('a');
    expect(removed, isTrue);
    expect(sonic.hasTemplate('a'), isFalse);
  });
}
