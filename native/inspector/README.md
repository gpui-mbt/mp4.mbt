# Native MP4 Inspector (gpui.mbt)

A minimal native file viewer built on `f4ah6o/gpui@0.7.2`. It reads an MP4
passed on the command line and renders the box tree, tracks and the first
samples using the portable `gpui-mbt/mp4/inspect` model.

```bash
# from the repository root
moon -C native/inspector check
moon -C native/inspector run src/main --target native -- <file.mp4>
moon -C native/inspector run src/main --target native -- <file.mp4> --smoke
```

`--smoke` presents one frame, destroys the window and exits. It requires a
working macOS GUI session; in a headless environment the host start fails and
the smoke is recorded as NOT_RUN.

## Limits

- The current implementation reads the whole file for the initial display.
  Range-read/virtual-list behavior is not yet implemented; large-file
  "no full read" is NOT_RUN.
- File selection is by command-line path; an OS file picker is not yet wired.
- Input/scroll/hex view interaction is not yet implemented.
