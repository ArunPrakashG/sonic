import 'dart:io';

// Usage:
// dart run benchmark/export_to_wiki.dart <path-to-wiki-clone>
// Or set env SONIC_WIKI_DIR to a path.
Future<void> main(List<String> args) async {
  final wikiDir = args.isNotEmpty
      ? args.first
      : (Platform.environment['SONIC_WIKI_DIR'] ?? '').trim();
  if (wikiDir.isEmpty) {
    stderr.writeln(
        'Provide the wiki folder path as an argument or set SONIC_WIKI_DIR.');
    exitCode = 1;
    return;
  }
  final src = File('benchmark/results.md');
  if (!await src.exists()) {
    stderr.writeln('benchmark/results.md not found. Run render_results first.');
    exitCode = 2;
    return;
  }
  final dst = File('$wikiDir/Benchmarks.md');
  await dst.parent.create(recursive: true);
  await src.copy(dst.path);
  stdout.writeln('Copied ${src.path} -> ${dst.path}');
}
