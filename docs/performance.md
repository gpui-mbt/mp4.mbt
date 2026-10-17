# 性能計測

数値は測定条件（fixture SHA、OS/arch、commit、warmup、反復）と一緒にのみ扱う。
未計測の項目を「高速化した」と主張しない。

## Native

```bash
moon run src/examples/bench --target native -- <fixture> <iterations>
/usr/bin/time -l moon run src/examples/bench --target native -- <fixture> 5
```

`src/examples/bench` は Sans I/O demux の read 要求回数、総 I/O バイト数、
track 数、sample 数を JSON で返す。経過時間と peak RSS は `/usr/bin/time -l`
などの外部ツールで測り、出力に fixture の SHA256 と commit を添える。

## Browser

`webdump` の read log（`mp4dump_read_log_json`）から read 回数と総 I/O バイト数を
取得できる。UI の描画時間は `performance.now()` で測り、巨大な sample table を
全件描画しないこと（仮想リスト）を確認する。

## 回帰条件

- `mdat` の payload を通常 demux が読まない（既存の read log E2E）。
- UI が巨大 table を全件描画しない（virtualized window）。
- range read の再試行回数が有限である（`required_input` のループ回数）。
- mux が大きい `mdat` を複製しない（API が payload を返さない）。

## 現状

初期 baseline は未計測（NOT_RUN）。CI では短い fixture の read 回数・I/O バイト数の
smoke のみを実行し、性能数値は測定条件とともに別途記録する。
