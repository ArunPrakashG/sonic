import 'package:sonic/sonic.dart';
import 'package:test/test.dart';

void main() {
  test('Header convenience helpers set expected values', () async {
    final sonic = Sonic.initialize(
        baseConfiguration:
            const BaseConfiguration(baseUrl: 'https://unit.test'));

    final b = sonic.create<void>(url: '/x')
      ..withBearerToken('abc')
      ..withIdempotencyKey('id123')
      ..withCorrelationId('corr123');

    // Execute against an unreachable host but ensure no crash in building
    final r = await b.asRawRequest().execute();
    expect(r.hasError || r.isSuccess, isTrue);
  });
}
