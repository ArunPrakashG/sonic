# Sonic Benchmarks

- Generated: 2025-10-12T13:27:13.450590
- Platform: linux 3.9.4 (stable) (Tue Sep 30 12:08:50 2025 -0700) on "linux_x64"

## GET json (1KB)

| Library | avg (ms) | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| http | 1.6 | 2 | 5 |
| dio | 0.8 | 1 | 2 |
| sonic | 0.8 | 1 | 2 |

## GET json (50KB)

| Library | avg (ms) | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| http | 4.3 | 11 | 14 |
| dio | 2.7 | 3 | 11 |
| sonic | 2.4 | 3 | 3 |

## GET bytes (100KB)

| Library | avg (ms) | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| http | 3.1 | 5 | 7 |
| dio | 3.0 | 5 | 6 |
| sonic | 3.0 | 5 | 6 |

## GET json (1MB)

| Library | avg (ms) | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| http | 33.6 | 48 | 60 |
| dio | 48.9 | 61 | 81 |
| sonic | 38.3 | 52 | 72 |

## stream download (5MB)

| Library | avg (ms) | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| http | 129.6 | 146 | 221 |
| dio | 126.4 | 199 | 209 |
| sonic | 120.3 | 173 | 301 |

## upload (1MB bytes)

| Library | avg (ms) | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| dio | 11.2 | 18 | 27 |
| sonic | 7.3 | 10 | 10 |

## parallel x20 (no dedup)

| Library | avg (ms) | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| dio | 11.0 | 14 | 17 |
| sonic | 11.6 | 13 | 33 |

## parallel x2 (no dedup)

| Library | avg (ms) | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| dio | 0.4 | 1 | 2 |
| sonic | 0.9 | 1 | 2 |

## parallel x20 (dedup on)

| Library | avg (ms) | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| sonic | 0.7 | 1 | 1 |

## retry (3 attempts)

| Library | avg (ms) | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| dio | 0.2 | 1 | 4 |
| sonic | 0.2 | 0 | 4 |

