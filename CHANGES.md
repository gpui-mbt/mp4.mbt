# Changelog

All notable changes to this project are recorded here.
The format is based on Keep a Changelog and the project uses milestone-based
versions (`M0`–`M5`); unreleased work is listed under `Unreleased`.

## Unreleased

### Added

- CI quality gates (`.github/workflows/ci.yml`): moon check/test for native and
  js targets, fmt diff, `.mbti` public API diff, pinned Rust oracle job with
  golden determinism check; Pages workflow deploys only `web/dist` after a
  successful CI run on main; contract documented in `docs/ci.md` (issue 0003).

- Rust oracle tool (`tools/oracle`, pinned upstream revision `1282b704`,
  Rust 1.94.0) with normalised JSON golden schema v1 (64-bit integers as
  decimal strings), fixture manifest with SHA256/attribution
  (`tests/fixtures/manifest.json`), 9 upstream fixtures and their goldens,
  and the deterministic regeneration script
  `tools/oracle/regenerate_fixtures.mbtx` (issue 0004).

- MoonBit module scaffold (`moon.mod` with `source = "src"`, `src/bytes`
  package) and the first core value type `FourCC` with black-box tests on
  Native and JS targets (issue 0002).

- Upstream reference and scope documents: `docs/upstream.md`,
  `docs/scope.md`, `LICENSE`, `NOTICE` (issue 0001).
