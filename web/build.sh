#!/bin/sh
# ブラウザデモの静的ビルド。
# MoonBit (js target) の webdump パッケージを ESM バンドルとして出力し、
# web/dist/ に GitHub Pages 用の静的ファイル一式を集める。
set -eu
cd "$(dirname "$0")/.."
moon build --release --target js src/webdump
mkdir -p web/dist
cp web/index.html web/app.js web/style.css web/dist/
cp _build/js/release/build/webdump/webdump.js web/dist/mp4.js
echo "built: web/dist/ (index.html app.js style.css mp4.js)"
