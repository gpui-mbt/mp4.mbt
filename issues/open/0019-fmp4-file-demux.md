# 0019: fMP4ファイル全体のincremental demuxerを作る

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M2 fragmented MP4
- 依存Issue: `0012`、`0017`、`0018`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
moof/mdatが複数並んだ単一のfMP4ファイルに対し、必要な範囲を段階的に読みながら全sampleを返す。

## 上流参照
- [src/demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_fmp4_file.rs)
- [tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)

## 実装手順（How）
1. `required_input`/`handle_input`/`tracks`/`next_sample`を通常版と整合する形で実装。初期化→segment境界走査→sample出力→次のsegmentの要求をphase化。
2. moofとmdatの間にfree等のtop-level boxを許容し、次のmoofが先に出る／サイズ0の終端boxが来た場合は上流どおり失敗とする。
3. 上流の制限：`tfhd.base_data_offset`がファイル絶対位置を指す形式には非対応であることをユーザー向けエラーにする。
4. segment内でDTS順、同時刻はtrackとdata位置に応じて安定順とし、sample entry変更通知をファイル全体で維持する。
5. 一度取得したsampleを全件queueに保持せず、offsetに基づく段階処理とEOFを管理する。

## 検証対象（What）
- [ ] 複数fragment・複数track・CTTSのsample順序とabsolute file data_offset。
- [ ] segmentを跨ぐsample entry変更、freeを挟む構造と空segmentの扱い。
- [ ] tfhd absolute base_data_offset、二つ続くmoof、mdat欠落で想定エラー。
- [ ] 大きいmdatで全読込を要求せず、Rust oracleと要求rangeを比較。

## 完了条件
- [ ] 通常demuxとは別のpublic typeを持ち、kind detectorから振り分け可能。
- [ ] Rustとのfragment単位・file単位のsemantic parityを両方示す。

## 非対象・境界
仕様外のtfhd形式を暗黙に読み替えない。
