# 0012: MP4／fMP4種別検出をRange I/Oで実装する

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M1 MP4読取
- 依存Issue: `0007`、`0008`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
ファイル拡張子に頼らず`moov/mvex`を検査して通常MP4とfragmented MP4を区別し、巨大/non-faststartも局所読み込みだけで扱う。

## 上流参照
- [src/demux_mp4_file_kind_detector.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_mp4_file_kind_detector.rs)
- [tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)
- [fuzz/fuzz_targets/fuzz_mp4_file_kind_detector.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_mp4_file_kind_detector.rs)

## 実装手順（How）
1. `Mp4FileKindDetector`の`required_input`→`handle_input`→`file_kind`状態機械を移植。`moov`内の`mvex`を判断基準にする。
2. `ftyp`→`free`などのtop-level boxを走査し、ヘッダーのsizeに従って`mdat`ペイロードをskipする。
3. I/Oへの要求は`position`と`size: Option`相当で通知。rangeが足りない場合は必要入力を保持し、短い入力と壊れたファイルの違いを維持する。
4. `size==0`、`large size`、`moov`が末尾、moov未発見、未知boxを明示的に扱う。

## 検証対象（What）
- [ ] 通常MP4、fMP4、non-faststart各fixtureでRustと同じkind。
- [ ] `mdat`が巨大でも全文を読まずkind判定できる。
- [ ] 不足data、異常box長、moovなし、終端付近のoverflowで固まらない。

## 完了条件
- [ ] Kind Detector単独でJS/Nativeに同じ結果を返す。
- [ ] 要求rangeと終了条件のテストがある。

## 非対象・境界
拡張子のみで判断しない。Hybrid MP4固有の最終化判定は0029で扱う。
