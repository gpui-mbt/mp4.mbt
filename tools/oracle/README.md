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

# decoded moov snapshot of one file (JSON on stdout)
cargo run --quiet -- moov-tree ../../tests/fixtures/upstream/black-h264-video.mp4

# moov boundary-case table (JSON on stdout)
cargo run --quiet -- moov-tree-cases

# sample table (stbl + accessor) snapshot of one file (JSON on stdout)
cargo run --quiet -- sample-tables ../../tests/fixtures/upstream/black-h264-video.mp4

# sample-table boundary-case table (JSON on stdout)
cargo run --quiet -- sample-tables-cases

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

### Moov tree case table and embedded moovs

`moov-tree <file>` extracts the top-level `moov` box from one file (a fixture
without `moov` is reported as `invalid_data`, "moov box not found") and decodes
it with the upstream `MoovBox`. It prints the normalised moov snapshot: the
`mvhd` fields, the per-track `tkhd` / optional `edts`+`elst` / `mdia` (`mdhd`,
`hdlr`) / `minf` (`media_header`, `dinf`→`dref`→`url `) fields described below.
64-bit values are decimal strings, fixed-point and other raw field bytes are
lowercase hex, and matrix values are comma-separated decimals.

`moov-tree-cases` runs the fixed whole-box boundary-case table in `src/main.rs`
(`moov_tree_cases`); `moov-tree-cases --moonbit` emits it as
`src/boxes/moov_tree_oracle_cases_test.mbt`. `moov-tree-fixtures --moonbit`
emits `src/boxes/moov_tree_oracle_fixtures_test.mbt` with the top-level `moov`
box bytes extracted from the two checked-in fixtures (`black-h264-video.mp4`
and `black-h264-fmp4.mp4`; the file header records each moov byte length and
sha256) and their expected snapshots. Both are consumed by
`src/boxes/moov_tree_oracle_test.mbt`:

```bash
cd tools/oracle
cargo run --quiet -- moov-tree-cases --moonbit > ../../src/boxes/moov_tree_oracle_cases_test.mbt
cargo run --quiet -- moov-tree-fixtures --moonbit > ../../src/boxes/moov_tree_oracle_fixtures_test.mbt
cd ../..
moon fmt   # canonical formatting is part of the generated files
```

The generated files are committed and must not be edited by hand. CI
regenerates every generated table in place, runs `moon fmt` and fails on any
`git diff`, so changing `moov_tree_cases` or `MOOV_TREE_FIXTURES` always
requires regenerating the MoonBit side in the same commit.

### Sample table case table and embedded stbls

`sample-tables <file>` extracts the top-level `moov` box from one file and, for
every track, decodes the `stbl` box and runs the upstream
`SampleTableAccessor`. Each track is emitted as `{track_index, status: "ok",
snapshot: [...]}`; accessor failures are embedded as the frozen
`error=accessor` lines instead of a `status`. A missing or malformed `moov`
yields `sample_tables: []` plus a `moov_error` object (`null` on success).
Snapshot lines: counts first, then every chunk, then every sample, with 0-based
loop indices in `chunk[i]`/`sample[i]` and explicit 1-based `.index=` values;
64-bit values are decimal strings.

`sample-tables-cases` runs the fixed whole-`stbl`-box boundary-case table in
`src/main.rs` (`sample_table_cases`); `sample-tables-cases --moonbit` emits it
as `src/boxes/sample_table_oracle_cases_test.mbt`. `sample-tables-fixtures
--moonbit` emits `src/boxes/sample_table_oracle_fixtures_test.mbt` with the
`stbl` box bytes re-encoded by upstream from every checked-in fixture (the file
header records each track's byte length and sha256) and their expected
snapshots. Both are consumed by `src/boxes/sample_table_oracle_test.mbt`:

```bash
cd tools/oracle
cargo run --quiet -- sample-tables-cases --moonbit > ../../src/boxes/sample_table_oracle_cases_test.mbt
cargo run --quiet -- sample-tables-fixtures --moonbit > ../../src/boxes/sample_table_oracle_fixtures_test.mbt
cd ../..
moon fmt   # canonical formatting is part of the generated files
```

The generated files are committed and must not be edited by hand. CI
regenerates every generated table in place, runs `moon fmt` and fails on any
`git diff`, so changing `sample_table_cases` or `SAMPLE_TABLE_FIXTURES` always
requires regenerating the MoonBit side in the same commit. Cases where upstream
is unspecified (duplicate binary-search keys from zero-count `stts`/`ctts`
runs with distinct deltas) are excluded from the differential on purpose and
covered by unit tests only.

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
- `moov-tree <file>` prints a separate document with `input` (name/size/sha256
  of the fixture, not the extracted `moov`) and `moov_tree`
  (`{"status": "ok", "snapshot": [...]}` or `{"status": "error",
  "error_kind": "...", "reason": "..."}`). `snapshot` is a flat array of
  `path=value` lines over the decoded `MoovBox`; the exact line list is frozen
  by `moov_snapshot` in `src/main.rs` and mirrored by
  `src/boxes/moov_tree_oracle_test.mbt`. Note that upstream
  `insufficient_buffer` errors carry an empty `reason`, so the differential
  test compares `reason` only when the oracle reports one.
- `sample-tables <file>` prints a separate document with `input`
  (name/size/sha256 of the fixture), `sample_tables` (one
  `{track_index, status: "ok", snapshot: [...]}` per track; accessor errors are
  embedded as the frozen `error=accessor` lines) and `moov_error` (`null` or
  `{error_kind, reason}` when the top-level `moov` could not be extracted or
  decoded). `snapshot` is a flat array of `sample_count` / `chunk[i].*` /
  `sample[i].*` lines frozen by `sample_table_snapshot` in `src/main.rs` and
  mirrored by `src/boxes/sample_table_oracle_test.mbt`.

Unavailable fixtures or oracle failures are reported as failures by
`regenerate_fixtures.mbtx`; they are never treated as "no difference".
