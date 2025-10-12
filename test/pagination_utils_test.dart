import 'package:sonic/src/pagination.dart';
import 'package:test/test.dart';

void main() {
  group('pagination utils', () {
    test('pluckValue plucks nested keys and indices', () {
      final data = {
        'meta': {
          'nextCursor': 'abc',
          'items': [
            {'id': 1},
            {'id': 2},
          ]
        }
      };
      expect(pluckValue(data, ''), data);
      expect(pluckValue(data, 'meta.nextCursor'), 'abc');
      expect(pluckValue(data, 'meta.items[0].id'), 1);
      expect(pluckValue(data, 'meta.items[1].id'), 2);
      expect(pluckValue(data, 'meta.items[2]'), isNull);
      expect(pluckValue(data, 'missing.key'), isNull);
    });

    test('addOrReplaceQueryParam replaces or adds key', () {
      final u1 = addOrReplaceQueryParam('https://a/b', 'cursor', 'x');
      expect(u1, 'https://a/b?cursor=x');
      final u2 = addOrReplaceQueryParam('https://a/b?cursor=x', 'cursor', 'y');
      expect(u2, 'https://a/b?cursor=y');
      final u3 = addOrReplaceQueryParam('https://a/b?z=1', 'cursor', 'x');
      expect(u3, anyOf('https://a/b?z=1&cursor=x', 'https://a/b?cursor=x&z=1'));
    });
  });
}
