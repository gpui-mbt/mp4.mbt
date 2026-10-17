# Native Inspector

`src/inspect` is the portable view model shared by the Native Inspector (and
usable by the Web Dump). It has no gpui/OS/DOM dependency:

- `box_rows` — flattened box tree lines
- `track_rows` — track table lines
- `sample_rows` — bounded virtual window over samples
- `hex_dump` — selected sample payload hex view

The gpui host is planned as a separate `native/inspector` module (UI → core
one-way dependency). It must use the same canonical model/JSON as `webdump`,
perform range reads (no whole-file load), and discard stale results on
re-selection/cancel.

## Native host

`native/inspector` is a separate MoonBit module (workspace `native/moon.work`)
that depends on `f4ah6o/gpui@0.7.2` and `gpui-mbt/mp4`. It renders the portable
rows with `SceneItem::text` and opens a native window.

```bash
moon -C native/inspector check
moon -C native/inspector run src/main --target native -- <file.mp4> --smoke
```

## Status

- Portable model: implemented and tested.
- gpui native host: implemented; `moon check` and window smoke PASS via
  `sh native/inspector/run.sh <fixture> --smoke` (42 rows).
- Range reads: only top-level headers, `moov`, demuxer ranges and the selected
  sample hex payload are read. A 524 MB sparse MP4 read only 2,094 bytes in the
  smoke test.
- `--pick` opens the macOS file dialog (`osascript`); it is implemented but
  not exercised in the non-interactive verification session.
- Interactive scroll / full virtual list: NOT_RUN (the current window renders a bounded 40-row sample window).
