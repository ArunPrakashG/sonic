import 'package:sonic/src/pagination.dart';
import 'package:test/test.dart';

void main() {
  test('makePaged constructs items and refs', () {
    final body = {
      'data': [
        {'id': 1},
        {'id': 2},
      ],
      'meta': {'nextCursor': 'abc'}
    };
    final headers = <String, List<String>>{};
    final paged = makePaged<int>(
      body: body,
      headers: headers,
      requestUrl: 'https://a/b?cursor=x',
      itemDecoder: (j) => j['id'] as int,
      itemsPath: 'data',
      nextCursorPath: 'meta.nextCursor',
    );
    expect(paged.items, [1, 2]);
    expect(paged.next?.url, 'https://a/b?cursor=abc');
    expect(paged.prev, isNull);
  });
}
