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

# boundary-case table for BoxHeader (JSON on stdout)
cargo run --quiet -- box-headers

# header-level box tree of one file (JSON on stdout)
cargo run --quiet -- box-tree ../../tests/fixtures/upstream/black-h264-video.mp4

# box-tree boundary-case table (JSON on stdout)
cargo run --quiet -- box-tree-cases

# regenerate all goldens and verify determinism + fixture hashes
cd ../..
moon run tools/oracle/regenerate_fixtures.mbtx

# fail instead of writing when a golden differs (CI / review use)
moon run tools/oracle/regenerate_fixtures.mbtx -- --check
```

### Box header case table

`box-headers` runs the fixed boundary-case table in `src/main.rs`
(`BOX_HEADER_CASES`) through the upstream `BoxHeader::decode_header_and_payload`
and prints one normalised JSON row per case (success/failure, box type bytes,
`u32`/`u64` size form, declared size, header/payload lengths, and the
wire-preserving header re-encode).

`box-headers --moonbit` emits the same table as the generated MoonBit test
file `src/box/box_header_oracle_cases_test.mbt`, consumed by
`src/box/box_header_oracle_test.mbt`:

```bash
cd tools/oracle
cargo run --quiet -- box-headers --moonbit > ../../src/box/box_header_oracle_cases_test.mbt
```

The file is committed and must not be edited by hand. CI regenerates it and
fails on any diff, so changing `BOX_HEADER_CASES` always requires regenerating
the MoonBit side in the same commit (and the generated code must stay
`moon fmt` clean).

### Box tree case table and embedded fixtures

`box-tree <file>` walks one file with the header-level policy shared with
`src/boxes/box_node.mbt`: `size==0` is accepted only at the top level, only
plain containers (`moov`/`trak`/`mdia`/`minf`/`stbl`/`edts`/`dinf`/`mvex`/
`moof`/`traf`/`mfra`/`udta`) are descended into, payload bytes are never
retained (only their range is recorded), and the depth/node limits use the
defaults (`64` / `65536`). It prints the observed node list
(`depth` / `type` / `start` / `header_bytes` / `declared_size` / `total_size`),
the upstream-decoded `ftyp` fields, or the failure kind.

`box-tree-cases` runs the fixed boundary-case table in `src/main.rs`
(`box_tree_cases`); `box-tree-cases --moonbit` emits it as
`src/boxes/box_tree_oracle_cases_test.mbt`. `box-tree-fixtures --moonbit` emits
`src/boxes/box_tree_oracle_fixtures_test.mbt` with the checked-in fixture bytes
(embedded via `include_bytes!`, so the file changes exactly when a fixture
changes) and their expected node lists/`ftyp` fields. Both are consumed by
`src/boxes/box_tree_oracle_test.mbt`:

```bash
cd tools/oracle
cargo run --quiet -- box-tree-cases --moonbit > ../../src/boxes/box_tree_oracle_cases_test.mbt
cargo run --quiet -- box-tree-fixtures --moonbit > ../../src/boxes/box_tree_oracle_fixtures_test.mbt
cd ../..
moon fmt   # canonical formatting is part of the generated files
```

The generated files are committed and must not be edited by hand. CI
regenerates every generated table in place, runs `moon fmt` and fails on any
`git diff`, so changing `box_tree_cases` or `BOX_TREE_FIXTURES` always requires
regenerating the MoonBit side in the same commit.

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
- `box-tree <file>` prints a separate document with `input`,
  `box_tree.ftyp` (upstream `FtypBox` fields) and `box_tree.tree`
  (`{"status": "ok", "nodes": [...]}` or `{"status": "error",
  "error_kind": "..."}`). Node `start` / `declared_size` / `total_size` are
  decimal strings; `type_hex` keeps the raw box-type bytes.

Unavailable fixtures or oracle failures are reported as failures by
`regenerate_fixtures.mbtx`; they are never treated as "no difference".
