import 'package:sonic/src/pagination.dart';
import 'package:test/test.dart';

void main() {
  test('advanceOffsetLimit adjusts offset and limit', () {
    final u1 =
        advanceOffsetLimit(url: 'https://a/b?limit=10&offset=0', pageSize: 10);
    expect(u1, 'https://a/b?limit=10&offset=10');
    final u2 = advanceOffsetLimit(
        url: 'https://a/b?limit=10&offset=10', pageSize: 10, next: false);
    expect(u2, 'https://a/b?limit=10&offset=0');
  });

  test('advancePageNumber adjusts page', () {
    final u1 = advancePageNumber(url: 'https://a/b?page=1');
    expect(u1, 'https://a/b?page=2');
    final u2 = advancePageNumber(url: 'https://a/b?page=2', next: false);
    expect(u2, 'https://a/b?page=1');
  });
}
