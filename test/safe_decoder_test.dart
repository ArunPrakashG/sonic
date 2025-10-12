import 'package:sonic/src/decoding.dart';
import 'package:test/test.dart';

void main() {
  test('safeDecoder catches exceptions and returns errors', () {
    final dec = safeDecoder<int>((j) => throw StateError('bad'));
    final r = dec({'x': 1});
    expect(r.isOk, isFalse);
    expect(r.value, isNull);
    expect(r.errors, isNotEmpty);
    expect(r.errors.first.message, contains('bad'));
  });
}
