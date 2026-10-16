# Project Agent Guide

This is the MoonBit port of [shiguredo/mp4-rs](https://github.com/shiguredo/mp4-rs).
A dependency-free, Sans I/O MP4/ISOBMFF mux/demux library.

## Project structure

- The module root (`moon.mod`) uses `source = "src"`, so every MoonBit package
  lives under `src/<package>/`. Packages are imported as `gpui-mbt/mp4/<package>`
  (for example `gpui-mbt/mp4/bytes`).
- Design rules, compatibility layers (`wire` / `semantic` / `surface`) and data
  contracts are in `docs/scope.md`. The pinned upstream reference and API
  mapping table are in `docs/upstream.md`.
- Work items are tracked as local Markdown issues under `issues/` (see
  `issues/polished/0000-implementation-roadmap.md`).
- Non-MoonBit assets: `tests/fixtures/` (fixtures and manifests),
  `tools/oracle/` (Rust oracle scripts), `web/` (browser demo assets).

## Commands

```bash
moon check                 # type check
moon check --target js     # type check a specific target
moon test                  # run tests (default target)
moon test --target js
moon test --target native
moon fmt                   # format code
moon info                  # update generated .mbti interfaces; review the diff
moon run src/examples/demux -- <file.mp4>   # native CLI example
```

- If `.mbti` diff is unchanged, the change did not alter the public API.
- Tests are grouped per package: `*_test.mbt` (black-box) and `*_wbtest.mbt`
  (white-box). Prefer black-box tests and public API.
- Use `moon test --update` to refresh snapshot tests, then review the diff.

## Conventions

- Every top-level block is separated by `///|`.
- `src/bytes` must stay dependency-free; higher layers follow the dependency
  direction documented in `docs/scope.md`. Never import UI/file/DOM APIs from
  core packages.
- Do not add placeholder or fake implementations. Public APIs are fixed with
  tests and docstring examples.
- Keep the exactly-known upstream API mapping in `docs/upstream.md` in sync with
  public API changes.
