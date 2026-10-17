# Changelog

All notable changes to this project are recorded here.
The format is based on Keep a Changelog and the project uses milestone-based
versions (`M0`–`M5`); unreleased work is listed under `Unreleased`.

## Unreleased

### Added

- Browser E2E workflow (`.github/workflows/browser-e2e.yml`) for dump,
  diff-lab and WebCodecs transcode; native inspector range reads and
  `--pick`; 100k mutation run recorded in `docs/verification.md`.

### Verified

- Ran the pinned Rust oracle (23 tests, goldens unchanged), Node diff lab
  (9/9 fixtures), browser dump/diff-lab E2E (20/20), Chrome WebCodecs
  transcode E2E (3/3), 10k mutation run, drift rehearsal, and a single-host
  benchmark. Results and the remaining NOT_RUN items are recorded in
  `docs/verification.md`.

### Added

- gpui.mbt Native MP4 Inspector (issue 0030): `native/inspector` separate
  module with a native window rendering box tree / tracks / samples via
  `SceneItem::text`, backed by the portable `src/inspect` model. `moon check`
  passes; window E2E and large-file range-read behavior are NOT_RUN.

- WebCodecs transcode demo (issue 0029): `web/transcode.html` +
  `web/transcode.js` decode a local MP4 with `VideoDecoder`, encode H.264 with
  `VideoEncoder`, and mux the chunks with the new `src/webtranscode`
  foreign-library session (`Mp4FileMuxer`). `webdump` gains
  `mp4dump_codec_config_json` for decoder descriptions. Node bundle smoke is
  verified; browser E2E is NOT_RUN.

- Fuzz / hardening (issue 0031): deterministic xorshift mutation, truncation
  corpus, `src/fuzz` tests and a native `examples/fuzz` runner; limits and
  seed/reproduction rules documented in `docs/fuzz.md`.
- Performance harness (issue 0032): `src/examples/bench` reports Sans I/O read
  counts, I/O bytes, tracks and samples as JSON; measurement/regression rules
  in `docs/performance.md` (timed baseline and browser metrics are NOT_RUN).
- Release and drift documentation (issues 0033–0034):
  `docs/compatibility.md`, `docs/release-checklist.md`,
  `docs/versioning.md`, `docs/upstream-drift.md`,
  `tools/upstream-drift/audit.py`, and a PR template. Publish/tag/release and
  the drift rehearsal remain NOT_RUN.

- Codec helpers (issues 0024–0026): H.264/H.265 Annex B and length-prefixed
  NAL parsing/conversion plus `avc1`/`hev1`/`hvc1` construction; AAC
  AudioSpecificConfig and ADTS parse/wrap plus `mp4a`; Opus sample entry;
  AV1 OBU/LEB128/sequence header, VP8 and VP9 frame-header parsing and
  `av01`/`vp08`/`vp09` construction.

- Subtitle sample entries (issue 0028): typed `stpp`/`wvtt`/`tx3g`,
  `vttC`/`ftab`/`BoxRecord`/`StyleRecord`/`FontRecord`, codec strings and
  mux handler/media-header mapping. Hybrid MP4 position contract and caller
  procedure are documented in `docs/hybrid_mp4.md` (issue 0027).

- Fragmented MP4 support (issues 0017–0021): typed `mvex`/`mehd`/`trex`,
  `moof`/`mfhd`/`traf`/`tfhd`/`tfdt`/`trun`, `sidx`, `mfra`/`tfra`/`mfro`,
  `RootBox` fMP4 variants, `Fmp4SegmentDemuxer`, incremental
  `Fmp4FileDemuxer` (absolute offsets, DTS ordering, entry-change notices,
  explicit rejection of absolute `tfhd.base_data_offset`), and
  `Fmp4SegmentMuxer` with init/media metadata, `sidx`, `mfra`, and roundtrip
  tests. Native `examples/fmp4` muxes a normal MP4 into `init.mp4` + media
  segments and reads them back. Rust-oracle comparison for the new fMP4 paths
  is recorded as UNVERIFIED (not yet run).

- Standard MP4 muxing (issues 0022–0023): `Mp4FileMuxer` with
  `initial_boxes_bytes` → payload → `append_sample` → `finalize`,
  `advance_position`, faststart reservation, `stts`/`ctts`/`stsc`/`stsz`/
  `stco`/`co64`/`stss` construction, `PositionMismatch`/`NoSyncSamples`/
  `AlreadyFinalized` errors, and a native `examples/mux` roundtrip CLI.

- Rust/WASM vs MoonBit/JS conformance diff lab (issue 0016): same MP4 bytes
  are parsed by the pinned-upstream Rust reference compiled to
  `wasm32-unknown-unknown` (`tools/lab-oracle`, a raw `cdylib` with the
  upstream `mp4_alloc`/`Vec` ABI shape — no wasm-bindgen) and by the MoonBit
  candidate, then compared field-path by field-path in
  `src/difflab` (pure MoonBit: allowlist normalization, no zero-filling of
  unknown fields, 64-bit decimal strings, `null` vs `0` distinguished,
  `PASS`/`FAIL`/`UNVERIFIED`/`NOT_RUN` verdicts, box trees compared
  order-independently with coverage gaps recorded as excluded instead of order
  diffs). `tools/oracle` emitters were extracted into `oracle_json.rs` shared
  by the native oracle and the wasm cdylib. `web/lab.html`/`lab.js` render the
  report (verdict, diff table, excluded list, run meta, fault-injection and
  download buttons); `web/run_lab.mjs` runs all manifest fixtures under Node
  and writes `web/lab-out/` reports which CI's new `diff-lab` job uploads as
  artifacts (issue 0016).

- Browser MP4 dump demo (issue 0015): `web/` gains a self-contained static app
  (`index.html`, `app.js`, `style.css`, `build.sh`) deployed to GitHub Pages
  via `.github/workflows/pages.yml`. `src/webdump` is a `foreign_library`
  MoonBit package exporting an 11-function ESM session API (`mp4dump_create` /
  `mp4dump_next_request` / `mp4dump_feed` / `mp4dump_state` /
  `mp4dump_cancel` / `mp4dump_report_json` / `mp4dump_tracks_json` /
  `mp4dump_samples_json` / `mp4dump_box_tree_json` / `mp4dump_read_log_json` /
  `mp4dump_error_json`); `web/app.js` answers each request with `File.slice`
  range reads, so `mdat` payload is never fetched and no DOM/File API enters
  core. `src/demux_report` is the shared canonical JSON renderer — the CLI's
  `--json` now delegates to it and gains a per-track `codec` field (first
  displayed sample entry, `null` when no sample was shown). Cancellation and
  re-selection discard stale async results via a generation counter in
  `app.js`; the UI uses a virtualized table for samples. A Playwright E2E
  (`web/e2e/e2e.mjs`, local tool) verifies file selection, rendering,
  re-selection, cancellation, error paths and the no-`mdat`-payload read log.
  CI gains a `web-build` job (bundle build + Node ESM smoke) (issue 0015).

- Native demux CLI example (issue 0014): `src/examples/demux` ports upstream
  `examples/demux.rs` as a native-only executable
  (`moon run src/examples/demux --target native -- <file.mp4>`). The Sans I/O
  `Mp4FileDemuxer` is driven by `required_input` absolute ranges read via
  `moonbitlang/async/fs` `File::read_exactly_at`; only this package touches the
  filesystem. Options: `--max-samples` (default 10), `--json` (64-bit values as
  decimal strings), `--buffer-size` (default 1048576, upstream's 1 MiB buffer;
  a `required_input.size` request above it fails explicitly instead of
  truncating the range like upstream does). Fixed exit codes: 0/2/3/4/5.
  `moon.mod` gains `moonbitlang/async@0.22.5` (example package only — core
  packages stay dependency-free Sans I/O). CI gains a `demux-cli` smoke job
  and now verifies the `codec-strings`/`kind-detector`/`demux` oracle case
  tables alongside the older modes (issue 0014).

- Sample tables and the sample table accessor (issue 0009): `src/boxes` gains
  the typed `stbl` subtree (`StblBox`, `StsdBox`, `SampleEntry` (unknown-only
  until 0010), `SttsBox` with `from_sample_deltas`, `CttsBox`, `CslgBox`,
  `SdtpBox`/`SdtpSampleFlags`, `StscBox`, `StszBox` (`Fixed`/`Variable`),
  `StcoBox`/`Co64Box`, `StssBox`) and `SampleTableAccessor` /
  `SampleAccessor` / `ChunkAccessor` with `SampleTableAccessorError`
  (all 8 upstream variants and messages). `MinfBox` requires `stbl` again
  (`stbl` was deferred in 0008). `src/bytes` gains `Either[A, B]`; `src/box`
  forwards `BaseBox` through it. The Rust oracle gains `sample-tables`,
  `sample-tables-cases` and `sample-tables-fixtures` modes; the generated
  52-case table and the `stbl`s of all nine fixtures are consumed by
  `src/boxes/sample_table_oracle_test.mbt` and diffed in CI.

- Movie/track boxes and timestamps (issue 0008): `src/boxes` gains the typed
  `moov` tree (`MoovBox`, `MvhdBox`, `TrakBox`, `TkhdBox`, `EdtsBox`/
  `ElstBox`, `MdiaBox`, `MdhdBox`, `HdlrBox`, `MinfBox`, `MediaHeader`
  (`SmhdBox`/`VmhdBox`/`SthdBox`/`NmhdBox`), `DinfBox`, `DrefBox`, `UrlBox`)
  with version 0/1 time and duration handling, first-child-wins duplicate
  rules, mandatory-child errors and `unknown_boxes` retention. `RootBox` gains
  the `Moov` variant. `src/bytes` gains `Mp4FileTime`, `Utf8String`,
  `LanguageCode`, `TrackKind`, `NonZeroU32` and the unsigned 8.8 fixed-point
  cursor helpers. `mvex`/`stbl` stay in `unknown_boxes` until issues 0017/0009
  (documented in `docs/upstream.md`). The Rust oracle gains `moov-tree`,
  `moov-tree-cases` and `moov-tree-fixtures` modes; the generated case table
  and two embedded-fixture moovs are consumed by
  `src/boxes/moov_tree_oracle_test.mbt` and diffed in CI.

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
