# Rust oracle for mp4.mbt

This directory contains the compatibility oracle: a small Rust program that
runs the pinned upstream `shiguredo/mp4-rs` implementation and prints a
normalised JSON description of the demux result. The MoonBit implementation
(candidate) is compared against the golden files this tool generates.

## Pinned reference

| Item | Value |
| --- | --- |
| Repository | `https://github.com/shiguredo/mp4-rs` |
| Revision | `1282b704f44184ec792e1549b5d31e0c4c54dc59` |
| Rust toolchain | see `rust-toolchain.toml` (1.94.0) |
| Golden schema | `schema_version: 1` |

The revision is pinned twice: in `Cargo.toml` (`rev = ...`) and in
`src/main.rs` (`UPSTREAM_SHA`, copied into every golden). Keep them in sync.

## Usage

```bash
cd tools/oracle

# one-off run (JSON on stdout)
cargo run --quiet -- demux ../../tests/fixtures/upstream/black-h264-video.mp4

# regenerate all goldens and verify determinism + fixture hashes
cd ../..
moon run tools/oracle/regenerate_fixtures.mbtx

# fail instead of writing when a golden differs (CI / review use)
moon run tools/oracle/regenerate_fixtures.mbtx -- --check
```

## Normalised schema (version 1)

- `input`: `name`, `size` and `sha256` of the fixture (size is a decimal string).
- `kind`: result of the incremental file kind detector (`mp4` / `fragmented-mp4`).
- `tracks[]`: `track_id`, `kind`, `timescale`, `duration`.
- `samples[]`: global time-ordered sample list with `index`, `track_id`,
  `sample_entry` (4CC or `null` when unchanged), `keyframe`, `dts`, `duration`,
  `pts_offset` (`null` when `ctts` is absent, kept distinct from `"0"`),
  `data_offset` (file-absolute) and `data_size`.
- All 64-bit integers are decimal strings so that no JSON Number rounding can
  hide a difference.
- Stage failures are recorded as `{"status": "error", ...}` with
  `classification` (`decode_error` / `sample_table_error` / `invalid_state` /
  `input_required`) and the upstream `error_kind` where available.

Unavailable fixtures or oracle failures are reported as failures by
`regenerate_fixtures.mbtx`; they are never treated as "no difference".
