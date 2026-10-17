# Fuzz / 不正入力の扱い

## fast suite

```bash
moon test --target native
moon run src/examples/fuzz --target native -- 1000
```

`src/fuzz` は xorshift32 による決定的な 1〜4 バイト mutation と切り詰めを生成する。
Box tree と demux に投入し、panic・無限ループ・無制限 allocation がないことを
確認する。seed は再現可能で、失敗時は `-- <iterations> <fixture>` の seed を
記録して回帰テストに追加する。

## 長時間 fuzz

`src/examples/fuzz` の iterations を増やして手動または別ワークフローで実行する。
実行時間・回数・target・seed・commit SHA・再現コマンドを記録し、未実行は
NOT_RUN として扱う（PASS と集計しない）。

## 上流対応

上流 Rust の fuzz target（box header / MP4 file demux / fMP4 segment demux /
mux）と PBT の全項目を移植したとは主張しない。MoonBit 側で実施可能な範囲を
この suite で継続的に検証し、未対応は未対応と明記する。
