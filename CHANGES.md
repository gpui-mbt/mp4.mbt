# Changelog

All notable changes to this project are recorded here.
The format is based on Keep a Changelog and the project uses milestone-based
versions (`M0`–`M5`); unreleased work is listed under `Unreleased`.

## Unreleased

### Added

- Root boxes and header-level box tree (issue 0007): `src/boxes` gains
  `FtypBox` (major/minor brand and compatible brands), `FreeBox`, `MdatBox`
  (payload range `data_offset`/`data_size`, no copy), `UnknownBox` (`decode`
  rejects `size==0`, `decode_top_level` accepts it and `Encode` preserves the
  wire form) and `RootBox` (`Free`/`Mdat`/`Unknown`). The `BoxNode` walker
  records depth/type/position/sizes without retaining payloads, rejects nested
  `size==0`, enforces depth/node limits (`BoxTreeOptions`, `flatten_box_tree`,
  `dump_line`). `src/bytes` gains `with_box_type` and
  `ReadCursor::from_view`. The Rust oracle gains `box-tree`,
  `box-tree-cases` and `box-tree-fixtures` modes; the generated case table and
  two embedded-fixture trees are consumed by
  `src/boxes/box_tree_oracle_test.mbt` and diffed in CI.

- Box envelope foundations (issue 0006): `src/box` gains `BoxSize`
  (`U32`/`U64`, variable-size markers, overflow-checked `with_payload_size`),
  `BoxHeader` (decode/encode, top-level `size==0` payload extraction,
  wire-preserving re-encode and `to_canonical`), `FullBoxFlags`/
  `FullBoxHeader` and the `BaseBox`/`FullBox` traits. `src/bytes` gains
  `BoxType` (`Normal`/`Uuid`), `Uuid`, the `Decode`/`Encode` traits with
  `decode_from`/`encode_to_bytes`, and `Mp4Error::with_box_type`. The Rust
  oracle gains a `box-headers` mode; its generated boundary-case table is
  consumed by `src/box/box_header_oracle_test.mbt` and diffed in CI.

- Bounds-safe byte/bit foundations (issue 0005): `src/bytes` gains the shared
  `Mp4Error`/`ErrorKind` classification, `ParseLimits`,
  `ReadCursor`/`WriteCursor` (Big Endian, position advances only on success),
  `FixedPointNumber` and explicit u64 → index/Double conversions; `src/bitstream`
  gains MSB-first `BitReader`/`BitWriter`.

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
