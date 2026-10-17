# Hybrid MP4 の書込位置契約

Hybrid MP4 は、通常の MP4 として再生できる `moov` を持ちながら、途中に
`moof`/`mdat` のフラグメントを差し込む形式である。mp4.mbt では
`Mp4FileMuxer` の絶対 offset 契約と `advance_position()` でこれを表現する。

## 手順

1. `muxer.initial_boxes_bytes()` を出力先の先頭へ書く。
2. フラグメントを書く場合は、caller が `moof`/`mdat` のヘッダーと payload を
   出力先へ書く。
3. 書いた非サンプル bytes の長さを `muxer.advance_position(size)` で通知する。
   `size > 0` のとき、次の `append_sample()` は必ず新しいチャンクを開始する。
4. サンプル payload を書き、`append_sample()` に**出力ファイル絶対位置**を渡す。
5. すべてのサンプルを書き終えたら `finalize()` を呼び、返された
   `offset_and_bytes_pairs()` を出力先へ適用する。先頭の `mdat` ヘッダーは
   ここで確定サイズに書き換わる。

`advance_position()` を呼ばずに非サンプル bytes を書いた場合、次の
`append_sample()` は `PositionMismatch` で失敗する。位置を黙って補正しない。

## 途中停止したファイル

最後に確定した `moof`/`mdat` の完了点までは fMP4 の segment demuxer
（`Fmp4SegmentDemuxer` / `Fmp4FileDemuxer`）で読める。書込途中の不完全な
フラグメントはエラーとして扱い、正常なセグメントと混同しない。

## 制限

- `advance_position()` は書込位置だけを進める。実際の bytes の書込みは caller が行う。
- reserved moov 領域が不足した場合、`finalize()` は faststart を諦めて moov を
  末尾へ置く。位置不一致や長さ overflow とは区別される。
- OS の fsync・電源断耐久性は保証しない。
