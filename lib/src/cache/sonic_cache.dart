import 'cached_object.dart';

class SonicCache {
  final _primitiveCache = <CachedObject<dynamic>>[];

  void add<T>(CachedObject<T> obj) {
    _primitiveCache.add(obj);
  }
}
