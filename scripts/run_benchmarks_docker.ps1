param(
  [string]$WikiDir
)

# Verify Docker is available
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
  Write-Error "Docker is not installed or not in PATH. Please install Docker Desktop."
  exit 1
}

$workDir = (Resolve-Path .).Path
$wikiVol = @()
$exportStep = ""

if ($WikiDir) {
  $wikiPath = (Resolve-Path $WikiDir).Path
  if (-not (Test-Path $wikiPath)) {
    Write-Error "Wiki directory not found: $WikiDir"
    exit 2
  }
  $wikiVol = @('-v', ($wikiPath + ':/wiki'))
  $exportStep = " && dart run benchmark/export_to_wiki.dart /wiki"
}

$dartBin = '/usr/lib/dart/bin/dart'
$cmds = "$dartBin --version && $dartBin pub get && $dartBin analyze && $dartBin test && $dartBin run benchmark/run_benchmarks.dart && $dartBin run benchmark/render_results.dart$exportStep"

$workBind = ($workDir + ':/work')
$dockerArgs = @(
  'run', '--rm',
  '-v', $workBind
) + $wikiVol + @(
  '-w', '/work',
  'dart:stable', 'bash', '-lc', $cmds
)

Write-Host "Running benchmarks in Docker..."
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Done. Results should be in benchmark/results.md and results-*.json"
