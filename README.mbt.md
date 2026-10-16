# mp4.mbt

MoonBit port of [shiguredo/mp4-rs](https://github.com/shiguredo/mp4-rs) — a dependency-free, Sans I/O MP4 mux/demux library.

This is an independent port, not an official shiguredo product. The Rust implementation at the pinned commit
[`1282b704f44184ec792e1549b5d31e0c4c54dc59`](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)
(Apache License 2.0, Copyright Shiguredo Inc.) is used as the behavioural reference (oracle) for compatibility testing.

## Status

The port is being implemented milestone by milestone. See [`issues/polished/0000-implementation-roadmap.md`](issues/polished/0000-implementation-roadmap.md)
for the plan and current progress. Unsupported features are never described here as supported.

- [ ] M0: scaffold, CI, Rust oracle and fixtures
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

The end-to-end demux API is not implemented yet (M1 in progress). The first public core type is
`FourCC` in the `gpui-mbt/mp4/bytes` package:

```mbt nocheck
///|
import @bytes from "gpui-mbt/mp4/bytes"

fn main {
  let ftyp = @bytes.FourCC::from_string("ftyp")!
  println(ftyp.to_string())
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

## Licence

Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE). Upstream-derived test fixtures remain under
the upstream Apache-2.0 terms and are recorded in `tests/fixtures/manifest.json` when added.
