# CI and quality gates

This document describes the CI jobs, the exact commands they run, and how
results are reported. The workflow files are `.github/workflows/ci.yml` and
`.github/workflows/pages.yml`.

## Job list

| Job | Target | Command | Purpose |
| --- | --- | --- | --- |
| `moon-check-native` | native | `moon check --target native` | type check |
| `moon-check-js` | js | `moon check --target js` | type check |
| `moon-test-native` | native | `moon test --target native` | unit tests |
| `moon-test-js` | js | `moon test --target js` | unit tests (same values/errors as native) |
| `moon-fmt` | — | `moon fmt --check` | formatting diff |
| `moon-info` | — | `moon info` + `git diff --exit-code -- '*.mbti'` | public API (`surface`) drift |
| `oracle` | Rust + MoonBit | `cargo test` (tools/oracle) and `moon run tools/oracle/regenerate_fixtures.mbtx -- --check` | pinned oracle tests, fixture hashes, golden determinism |

- Required checks for merge (branch protection): the 5 MoonBit jobs plus
  `oracle`. Configure them in the repository settings; this list is the
  source of truth.
- The oracle job pins Rust 1.94.0 via `tools/oracle/rust-toolchain.toml`
  (`RUSTUP_TOOLCHAIN` is set in the workflow as well) and caches
  `~/.cargo/registry` + `~/.cargo/git` keyed by `tools/oracle/Cargo.lock`.
  It never clones upstream testdata at a floating revision: fixtures are
  committed and verified by SHA256.
- MoonBit toolchain: CI installs the current stable via the official installer
  and logs `moon version --all` in every job. Record the tested version in the
  PR when it changes.

## Result states

- Every job reports PASS or FAIL. Job-level SKIP (for example, no fixture
  available) is displayed as SKIP and is never aggregated as PASS.
- `moon test` output includes the per-target test counts; failure output is
  preserved in the job log.
- The golden check writes no files in CI (`--check`): a diff fails the job so a
  reviewer can inspect it locally instead of CI silently rewriting goldens.

## Local reproduction

```bash
# MoonBit checks (same commands as CI)
moon check --target native
moon check --target js
moon test --target native
moon test --target js
moon fmt --check
moon info && git diff --exit-code -- '*.mbti'

# Oracle (same commands as CI)
cd tools/oracle && cargo test && cd ../..
moon run tools/oracle/regenerate_fixtures.mbtx -- --check
```

## Failure injection (CI contract verification)

The CI contract states these behaviours; verify them in a scratch clone if CI
runners are not available:

1. Inject a syntax error → `moon check` must fail (the job turns red).
2. Modify a golden file → `regenerate_fixtures.mbtx -- --check` must fail.
3. Remove/rename a fixture → the same check reports a failure (never PASS).
4. Change a public API without updating `.mbti` → `moon info` produces a diff
   and the `moon-info` job fails.
5. Fail any MoonBit test → the Pages deploy job is not started because it
   requires `workflow_run.conclusion == success` on `main`.

## Pages deployment

`pages.yml` runs after a successful `CI` run on `main` only. It deploys the
limited output directory `web/dist` (never the whole repository). Until the
web demo (issue 0015) exists, the workflow logs an explicit skip message and
deploys nothing.
