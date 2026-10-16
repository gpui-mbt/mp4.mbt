# 0018: 初期化＋メディアセグメントのSans I/O demuxerを作る

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M2 fragmented MP4
- 依存Issue: `0010`、`0017`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
init segment(`ftyp+moov/mvex`)と後続`moof/mdat`列からsample metadataとpayload位置を取り出す。

## 上流参照
- [src/demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_fmp4_segment.rs)
- [tests/test_demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_segment.rs)

## 実装手順（How）
1. `handle_init_segment`、`tracks`、`handle_media_segment`相当のAPIを実装。トラックIDとtrexデフォルトを接続し、skip対象トラックのtrafも安全に処理する。
2. segで返す`Sample.data_offset`は`handle_media_segment()`へ渡したバッファ先頭からの相対位置。通常MP4のファイル絶対位置と混同しない。
3. moof前のstyp/sidx、間のfree、mdat後の付加boxを上流の受理範囲に揃え、default valuesの継承とoffset境界を確かめる。
4. sample entryの最初の通知と変更時通知、keyframe、DTS/CTTS/timescaleを再現する。
5. 初期化なしメディア投入、segment内broken offset、multiple traf、不明track IDといった失敗を分類する。

## 検証対象（What）
- [ ] 上流black-h264-fmp4と生成init/media群で全sampleのoffset/size/DTSが一致。
- [ ] moof/mdatの周辺にfree/sidxがある場合の相対位置が合う。
- [ ] initなし/mdatなし/範囲外trun/空payloadを適切に拒否。
- [ ] 複数セグメント継続時のdecode timeとentry変更を検証。

## 完了条件
- [ ] 上流のsegment demux APIで同じ観測値を提供する。
- [ ] sample payloadを正確にsliceして取り出せる。

## 非対象・境界
単一巨大ファイルのincremental demuxは0019で実装する。
