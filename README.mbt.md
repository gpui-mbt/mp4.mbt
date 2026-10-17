# mp4.mbt

MoonBit port of [shiguredo/mp4-rs](https://github.com/shiguredo/mp4-rs) — a dependency-free, Sans I/O MP4 mux/demux library.

This is an independent port, not an official shiguredo product. The Rust implementation at the pinned commit
[`1282b704f44184ec792e1549b5d31e0c4c54dc59`](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)
(Apache License 2.0, Copyright Shiguredo Inc.) is used as the behavioural reference (oracle) for compatibility testing.

## Status

The port is being implemented milestone by milestone. See [`issues/polished/0000-implementation-roadmap.md`](issues/polished/0000-implementation-roadmap.md)
for the plan and current progress. Unsupported features are never described here as supported.

- [x] M0: scaffold, CI, Rust oracle and fixtures
- [ ] M1: boxes, read-only MP4 demux, Native CLI, Web dump, Rust diff lab
- [ ] M2: fragmented MP4 demux/mux
- [ ] M3: standard MP4 mux
- [ ] M4: bitstream helpers, subtitles, Hybrid MP4
- [ ] M5: WebCodecs demo, native inspector, fuzz, performance, release docs

## Scope and compatibility

- Target / responsibility boundaries: [`docs/scope.md`](./docs/scope.md)
- Pinned upstream reference, licence notes and API mapping: [`docs/upstream.md`](./docs/upstream.md)

Compatibility is stated in three layers: `wire` (serialised MP4 bytes), `semantic` (tracks, samples, timestamps,
offsets, failure classification) and `surface` (public MoonBit API). M1 uses `semantic` matching against the
Rust oracle as the default criterion.

## Usage

### Demux CLI (native)

A `moon run` executable port of upstream `examples/demux.rs` lives at
`src/examples/demux` (native target only; the demuxer core stays Sans I/O — only
this package touches the filesystem):

```bash
moon run src/examples/demux --target native -- <file.mp4>
moon run src/examples/demux --target native -- <file.mp4> --json --max-samples 20
```

- `<file.mp4>`: MP4 file path (required)
- `--max-samples <N>`: number of leading samples to print (default `10`; `0` prints
  track metadata only)
- `--json`: emit JSON instead of text. 64-bit values (`duration`, `timestamp`,
  `composition_time_offset`, `data_offset`) are decimal **strings**, so they survive
  JavaScript JSON consumers without precision loss
- `--buffer-size <bytes>`: maximum bytes read for a single `required_input` range
  (default `1048576`, matching upstream's 1 MiB buffer). Unlike upstream, a
  `required_input.size` request larger than this limit fails explicitly with exit
  code `4` instead of silently truncating the requested range

Exit codes: `0` success, `2` invalid arguments, `3` I/O error (missing file,
unexpected EOF), `4` required range exceeds `--buffer-size`, `5` demux error.

Example output:

```text
Found 1 track

Track 1:
  Track ID: 1
  Kind: video
  Duration: 512 (timescale: 12800)

Samples:
  Sample 1:
    Track ID: 1
    Sample entry: avc1
    Keyframe: true
    Timestamp: 0
    Duration: 512
    Composition time offset: none
    Data offset: 0x30
    Data size: 796 bytes
```

### Browser MP4 Dump (JS)

A static browser demo lives in `web/` and is deployed to GitHub Pages. Drop an
MP4 file onto the page to see its box tree, tracks, samples and a canonical
JSON report — the same schema the native CLI emits. Parsing runs entirely in
the browser via `File.slice` range reads driven by the Sans I/O demuxer; the
file is never uploaded and `mdat` payload bytes are never read.

```bash
sh web/build.sh   # builds the JS-target MoonBit bundle into web/dist/
```

The page is plain HTML/CSS/JS — `web/dist` is self-contained and can be served
by any static file server (e.g. `python3 -m http.server -d web/dist`).

`src/webdump` is the adapter package: a `foreign_library` MoonBit package that
exports a small session API (`mp4dump_create` / `mp4dump_next_request` /
`mp4dump_feed` / `mp4dump_state` / `mp4dump_cancel` / `mp4dump_*_json`) as an
ESM bundle. All DOM and `File` API handling stays in `web/app.js`; the session
machine itself is pure MoonBit and shares `src/demux_report` canonical JSON
with the CLI.

A Playwright E2E (`web/e2e/e2e.mjs`, local verification tool — browsers are
not downloaded in CI) drives headless Chromium through file selection, box
tree / track / sample rendering, re-selection, cancellation and error paths,
and asserts the read log never spans `mdat` payload:

```bash
PLAYWRIGHT_PATH=<path-to-playwright> node web/e2e/e2e.mjs
```

### Diff Lab — Rust/WASM vs MoonBit/JS

`web/lab.html` is a conformance lab: the same MP4 bytes are parsed by the
pinned-upstream **Rust reference compiled to wasm** (`tools/lab-oracle`, a raw
`cdylib` with the `mp4_alloc`/`Vec` ABI shape of upstream `dump_wasm`) and by
the **MoonBit/JS candidate**, then compared field-path by field-path. The
report carries the pinned upstream SHA, fixture checksum and toolchain meta,
and distinguishes `PASS` / `FAIL` / `UNVERIFIED` / `NOT_RUN` — an oracle or
candidate that never ran is never reported as a match. 64-bit values compare
as decimal strings and `null` is never conflated with `0`.

The comparator is pure MoonBit (`src/difflab`, allowlist normalization — no
zero-filling of unknown fields) exported as `mp4lab_compare_json` /
`mp4lab_unverified_json` from the same ESM bundle. A Node runner regenerates
the report set for every fixture in `tests/fixtures/manifest.json` and is what
CI runs:

```bash
sh web/build.sh        # builds mp4.js + tools/lab-oracle → web/dist/oracle.wasm
node web/run_lab.mjs   # writes web/lab-out/*.report.json + summary.json
```

CI's `diff-lab` job runs the above and uploads `web/lab-out/` as an artifact;
the browser page additionally proves both engines actually execute (engine
log) and includes a fault-injection button that mutates one sample duration to
demonstrate a real `FAIL` at `samples[0].duration`.

### Library

The Sans I/O demuxer for normal MP4 files lives in `gpui-mbt/mp4/demux`
(`Mp4FileDemuxer`, `Mp4FileKindDetector`, `RequiredInput`/`Input`,
`TrackInfo`, `Sample`, `Duration`, `DemuxError`). Callers feed exactly the
absolute byte ranges the demuxer asks for via `required_input()` — the library
itself performs no I/O.

The foundation packages are
`gpui-mbt/mp4/bytes` (bounds-safe Big Endian cursors, `Mp4Error` classification, `ParseLimits`,
`FourCC`, `BoxType`/`Uuid`, `Decode`/`Encode`), `gpui-mbt/mp4/bitstream` (MSB-first
`BitReader`/`BitWriter`), `gpui-mbt/mp4/box` (box envelope: `BoxHeader`/`BoxSize`,
`FullBox` headers) and `gpui-mbt/mp4/boxes` (root boxes `ftyp`/`free`/`mdat`, the
box tree walker, `moov`/`stbl` tables, `SampleTableAccessor` and typed sample
entries):

```mbt nocheck
///|
import @bytes from "gpui-mbt/mp4/bytes"
import @box from "gpui-mbt/mp4/box"
import @boxes from "gpui-mbt/mp4/boxes"

fn main {
  let writer = @bytes.WriteCursor::new()
  writer.write_u16(0x1234)
  writer.write_u32(0x56789ABC)
  println(writer.to_bytes().length()) // 6

  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x08mdat")
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  println(header.box_size().get()) // 8
  println(payload.length()) // 0

  let tree = try! @boxes.build_box_tree(
    @bytes.ReadCursor::new(b"\x00\x00\x00\x0Cmdat\x11\x22\x33\x44"),
  )
  for entry in @boxes.flatten_box_tree(tree) {
    let (depth, node) = entry
    println(node.dump_line(depth)) // d=1 mdat start=0 size=12 header=8 payload=4
  }
}
```

## Development

Verified commands (run from the repository root, moon 0.1.20261012):

```bash
moon check                      # type check (default target)
moon check --target js
moon test --target native       # unit tests
moon test --target js
moon fmt                        # format
moon info                       # regenerate public interface (.mbti) files
```

CI jobs, required checks and local reproduction steps are documented in
[`docs/ci.md`](./docs/ci.md).

## Licence

Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE). Upstream-derived test fixtures remain under
the upstream Apache-2.0 terms and are recorded in `tests/fixtures/manifest.json` when added.
