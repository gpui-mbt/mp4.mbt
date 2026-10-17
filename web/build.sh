#!/bin/sh
# ブラウザデモの静的ビルド。
# MoonBit (js target) の webdump パッケージを ESM バンドルとして出力し、
# web/dist/ に GitHub Pages 用の静的ファイル一式を集める。
#
# Diff Lab 用の Rust/WASM oracle (tools/lab-oracle, wasm32-unknown-unknown) は
# cargo + wasm target が利用できる場合のみビルドする。欠落時は lab ページ側が
# UNVERIFIED 判定に自動で落ちるため、デモ本体は常にビルドできる。
set -eu
cd "$(dirname "$0")/.."
moon build --release --target js src/webdump
mkdir -p web/dist
cp web/index.html web/app.js web/lab.html web/lab.js web/style.css web/dist/
cp _build/js/release/build/webdump/webdump.js web/dist/mp4.js

if command -v cargo >/dev/null 2>&1; then
  # rust-toolchain.toml は作業ディレクトリ起点で解決されるため cd が必要
  (cd tools/lab-oracle && cargo build --release --target wasm32-unknown-unknown)
  cp tools/lab-oracle/target/wasm32-unknown-unknown/release/lab_oracle.wasm \
    web/dist/oracle.wasm
  echo "built: web/dist/ (index.html app.js lab.html lab.js style.css mp4.js oracle.wasm)"
else
  echo "built: web/dist/ (index.html app.js lab.html lab.js style.css mp4.js; oracle.wasm SKIPPED: cargo not found)"
fi
