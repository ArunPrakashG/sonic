# Benchmarks

This folder contains a simple micro-benchmark harness to compare Sonic with other popular HTTP clients on common scenarios.

Scenarios:

- GET JSON (small payload ~1KB)
- GET JSON (medium payload ~50KB)
- GET bytes (100KB)
- GET JSON (large payload ~1MB)
- Streaming download (5MB)
- Upload (1MB)
- Parallel GET x 20 (dedup off)
- Parallel GET x 20 (Sonic dedup on)
- Retry on 500 (3 attempts)

The numbers are indicative and will vary based on your machine.

Notes on fairness:

- Sonic uses Dio internally for transport. For apples-to-apples, we disable dedup in the "no dedup" scenario.
- Sonic can appear faster when features like deduplication collapse work (see the dedicated dedup scenario).
- Minor differences across runs (sub-millisecond) are normal and usually noise.
- For more robust comparisons, run on multiple OSes and list each as separate results files (the runner now writes results-<os>.json).

How to run:

- Native:

  - dart run benchmark/run_benchmarks.dart
  - dart run benchmark/render_results.dart

- Docker (recommended for consistency):
  - scripts/run_benchmarks_docker.ps1
  - scripts/run_benchmarks_docker.ps1 -WikiDir <path-to-wiki-clone>

Outputs:

- benchmark/results.json: machine-readable results
- benchmark/results.md: Markdown table suitable for the wiki
