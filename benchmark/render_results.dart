import 'dart:convert';
import 'dart:io';

/// Render a Markdown report from a results map of the form:
/// { scenario: { library: { avgMs, p90Ms, p99Ms } } }
String renderMarkdown(Map<String, dynamic> results,
    {DateTime? generatedAt, String? platformInfo}) {
  final buf = StringBuffer();
  buf.writeln('# Sonic Benchmarks');
  buf.writeln();
  if (generatedAt != null || platformInfo != null) {
    buf.writeln(
        '- Generated: ${(generatedAt ?? DateTime.now()).toIso8601String()}');
    buf.writeln(
        '- Platform: ${platformInfo ?? '${Platform.operatingSystem} ${Platform.version}'}');
    buf.writeln();
  }
  for (final scenario in results.keys) {
    final entries =
        (results[scenario] as Map<String, dynamic>).cast<String, dynamic>();
    buf.writeln('## $scenario');
    buf.writeln();
    buf.writeln('| Library | avg (ms) | p90 (ms) | p99 (ms) |');
    buf.writeln('|---|---:|---:|---:|');
    for (final lib in entries.keys) {
      final stats = (entries[lib] as Map).cast<String, dynamic>();
      final avg = (stats['avgMs'] as num).toStringAsFixed(1);
      final p90 = stats['p90Ms'] as num;
      final p99 = stats['p99Ms'] as num;
      buf.writeln('| $lib | $avg | $p90 | $p99 |');
    }
    buf.writeln();
  }
  return buf.toString();
}

Future<void> main() async {
  // Prefer OS-tagged file if present; fallback to results.json
  final osTag = Platform.operatingSystem;
  final candidates = [
    'benchmark/results-$osTag.json',
    'benchmark/results.json',
  ];
  File? file;
  for (final p in candidates) {
    final f = File(p);
    if (await f.exists()) {
      file = f;
      break;
    }
  }
  if (file == null) {
    stderr.writeln(
        'No results file found. Run benchmark/run_benchmarks.dart first.');
    exitCode = 1;
    return;
  }
  final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final md = renderMarkdown(map, generatedAt: DateTime.now());
  final out = File('benchmark/results.md');
  await out.writeAsString(md);
  stdout.writeln(md);
}
