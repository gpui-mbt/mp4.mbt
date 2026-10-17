# Verification record

Date: 2026-10-17 (Asia/Tokyo). Environment: macOS 26.5.2 / arm64, MoonBit
`0.1.20261012`, Rust oracle verified with installed `1.98.1` (CI pins 1.94.0),
Google Chrome 155.0.8059.84 for browser E2E.

## PASS

| Check | Command | Result |
| --- | --- | --- |
| MoonBit native tests | `moon test --target native` | 508 passed |
| MoonBit JS tests | `moon test --target js` | 492 passed |
| Type check JS | `moon check --target js` | clean |
| Format | `moon fmt --check` | clean |
| Public API | `moon info` | no diff |
| Native inspector module | `moon -C native/inspector check` | clean |
| Native inspector window smoke | `sh native/inspector/run.sh <fixture> --smoke --status /tmp/status.txt` | PASS, 27 rows |
| Oracle unit tests | `cd tools/oracle && cargo test` | 23 passed |
| Oracle goldens | `moon run tools/oracle/regenerate_fixtures.mbtx -- --check` | 9/9 unchanged |
| Diff lab (Node) | `node web/run_lab.mjs` | 9 fixtures PASS |
| Browser E2E (dump + diff lab) | `PLAYWRIGHT_PATH=/tmp/pw node web/e2e/e2e.mjs` | 20/20 |
| WebCodecs E2E (Chrome) | `PLAYWRIGHT_PATH=/tmp/pw CHANNEL=chrome node web/e2e/transcode.mjs` | 3/3, output MP4 written |
| Transcoded output | MoonBit demux + Rust oracle | tracks/samples/offset match |
| Long mutation run | `moon run src/examples/fuzz --target native -- 10000` | 10,000 iterations, no panic |
| Drift rehearsal | `python3 tools/upstream-drift/audit.py <old> <new>` | contract delta detected |
| Benchmark | `_build/native/debug/build/examples/bench/bench.exe <fixture> 50` | 250 reads, 45,950 I/O bytes, 0.30 s, 2.8 MB peak RSS |

Notes:

- MoonBit commands were run with a workspace-local `MOON_HOME` because the
  machine's global registry index was stale relative to `moon.mod`.
- The Rust oracle was built with the installed `1.98.1` toolchain and a
  workspace-local `CARGO_HOME`; CI uses the pinned `1.94.0`.
- `web/e2e/transcode.mjs` requires a browser with H.264 WebCodecs support;
  headless Chromium without H.264 takes the explicit Disabled path instead.

## NOT_RUN

| Check | Reason |
| --- | --- |

| Native inspector file picker / scroll / hex interaction | Not implemented yet; the host renders the portable rows. |
| Large-file (500 MB+) no-full-read measurement | Not measured. |
| CI-run browser E2E | Playwright browsers are not downloaded in CI; the E2E is a local/manual check. |
| Performance regression thresholds | Only a single-machine baseline was captured. |
