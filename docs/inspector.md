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

## Status

- Portable model: implemented and tested.
- gpui native host / file picker / window E2E: **NOT_RUN** (no gpui host
  integration in this environment).
- Large-file "no full read" measurement: **NOT_RUN**.
