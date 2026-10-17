#!/bin/sh
# Build the gpui macOS dylib and run the inspector with the library path set.
# Usage: sh native/inspector/run.sh <file.mp4> [--smoke] [--status PATH]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
GPUI="$ROOT/native/.mooncakes/f4ah6o/gpui"
APP="$ROOT/native/_build/macos/MP4Inspector.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
xcrun clang -dynamiclib -fobjc-arc -Wall -Wextra -Werror \
  "$GPUI/platform/macos/native.m" \
  "$GPUI/platform/macos/accessibility.m" \
  "$GPUI/platform/macos_text/core_text.c" \
  -framework AppKit -framework QuartzCore -framework Metal \
  -framework CoreText -framework CoreGraphics -framework CoreFoundation \
  -o "$APP/Contents/Frameworks/libgpui_macos.dylib"
(cd "$ROOT" && moon -C native/inspector build src/main)
cp "$ROOT/native/_build/native/debug/build/gpui-mbt/mp4-inspector/src/main/main.exe" \
  "$APP/Contents/MacOS/mp4-inspector"
exec env GPUI_MACOS_LIBRARY="$APP/Contents/Frameworks/libgpui_macos.dylib" \
  "$APP/Contents/MacOS/mp4-inspector" "$@"
