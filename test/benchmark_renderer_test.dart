import 'package:test/test.dart';

import '../benchmark/render_results.dart' as render;

void main() {
  test('renderMarkdown outputs expected table for sample data', () {
    final sample = <String, dynamic>{
      'Scenario A': {
        'http': {'avgMs': 1.2, 'p90Ms': 3, 'p99Ms': 4},
        'dio': {'avgMs': 0.9, 'p90Ms': 2, 'p99Ms': 3},
        'sonic': {'avgMs': 0.8, 'p90Ms': 2, 'p99Ms': 2},
      },
    };
    final md = render.renderMarkdown(sample,
        generatedAt: DateTime.parse('2025-01-01T00:00:00Z'),
        platformInfo: 'test-platform 1.0');

    // Basic checks
    expect(md, contains('# Sonic Benchmarks'));
    expect(md, contains('## Scenario A'));
    expect(md, contains('| Library | avg (ms) | p90 (ms) | p99 (ms) |'));
    // Row formatting and decimal for avg
    expect(md, contains('| http | 1.2 | 3 | 4 |'));
    expect(md, contains('| dio | 0.9 | 2 | 3 |'));
    expect(md, contains('| sonic | 0.8 | 2 | 2 |'));
  });

  test('renderMarkdown handles integer avgMs gracefully', () {
    final sample = <String, dynamic>{
      'Scenario B': {
        'http': {'avgMs': 2, 'p90Ms': 5, 'p99Ms': 9},
      },
    };
    final md = render.renderMarkdown(sample,
        generatedAt: DateTime.parse('2025-01-01T00:00:00Z'),
        platformInfo: 'test');
    expect(md, contains('| http | 2.0 | 5 | 9 |'));
  });
}
