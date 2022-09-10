import 'package:meta/meta.dart';

@immutable
class SonicProgress {
  const SonicProgress({
    required this.total,
    required this.current,
  });

  final int total;
  final int current;

  @override
  bool operator ==(covariant SonicProgress other) {
    if (identical(this, other)) {
      return true;
    }

    return other.total == total && other.current == current;
  }

  @override
  int get hashCode => total.hashCode ^ current.hashCode;
}
