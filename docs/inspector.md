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
- gpui native host: implemented; `moon check` PASS. Window smoke is **NOT_RUN**
  in this headless session (macOS host start fails without a GUI session).
- File picker, interaction, large-file range read / virtual list: **NOT_RUN**.
