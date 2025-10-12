param(
  [string]$WikiDir = $env:SONIC_WIKI_DIR
)

# Ensure Dart is available
$dart = Get-Command dart -ErrorAction SilentlyContinue
if (-not $dart) {
  Write-Error "Dart SDK not found in PATH. Install Dart or run via Docker."
  exit 1
}

# Analyze
Write-Host "Running analyzer..."
dart analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Tests
Write-Host "Running tests..."
dart test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Benchmarks
Write-Host "Running benchmarks..."
dart run benchmark/run_benchmarks.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Rendering results..."
dart run benchmark/render_results.dart | Out-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($WikiDir) {
  Write-Host "Exporting to wiki: $WikiDir"
  dart run benchmark/export_to_wiki.dart $WikiDir
}
