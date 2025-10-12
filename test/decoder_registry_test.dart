import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

class Foo {
  Foo(this.x);
  final int x;
}

void main() {
  test('default decoders are registered on initialize', () async {
    final s = Sonic.initialize(
      baseConfiguration:
          const BaseConfiguration(baseUrl: 'https://example.com'),
    );
    expect(s.hasDecoder<Map<String, dynamic>>(), isTrue);
    expect(s.hasDecoder<List<dynamic>>(), isTrue);
    expect(s.hasDecoder<String>(), isTrue);
    expect(s.hasDecoder<int>(), isTrue);
    expect(s.hasDecoder<double>(), isTrue);
    expect(s.hasDecoder<bool>(), isTrue);
  });

  test('custom decoder register/unregister works', () {
    final s = Sonic.initialize(
      baseConfiguration:
          const BaseConfiguration(baseUrl: 'https://example.com'),
    );

    expect(s.hasDecoder<Foo>(), isFalse);
    s.registerDecoder<Foo>((j) => Foo((j as Map<String, dynamic>)['x'] as int));
    expect(s.hasDecoder<Foo>(), isTrue);
    final removed = s.unregisterDecoder<Foo>();
    expect(removed, isTrue);
    expect(s.hasDecoder<Foo>(), isFalse);
  });

  test('registerJsonPair registers decoder side too', () {
    final s = Sonic.initialize(
      baseConfiguration:
          const BaseConfiguration(baseUrl: 'https://example.com'),
    );

    s.registerJsonPair<Foo>(
      encoder: (f) => {'x': f.x},
      decoder: (j) => Foo((j as Map<String, dynamic>)['x'] as int),
    );
    expect(s.hasDecoder<Foo>(), isTrue);
  });
}
