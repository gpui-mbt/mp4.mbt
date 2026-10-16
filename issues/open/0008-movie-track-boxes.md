# 0008: moov／trak／mdia／minfと時刻情報を移植する

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M1 MP4読取
- 依存Issue: `0007`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`（`develop` の調査時HEAD）

## 目的
MP4の映画単位とトラック単位を構造化し、track ID・kind・duration・timescaleを正確に取り出す。

## 上流参照
- [src/boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_moov_tree.rs)
- [tests/test_boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_moov_tree.rs)
- [src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs)

## 実装手順（How）
1. `mvhd`/`tkhd`/`mdhd`/`hdlr`/`minf`/`dinf`/`edts`/`elst`等を上流の型に対応させる。version 0/1の時間・duration幅の違いを実装する。
2. `hdlr`の音声・映像・字幕に対応するTrackKindと未知handlerの扱いを定義する。`sthd`/`nmhd`/`vmhd`/`smhd`の合法な組を明示。
3. Moov構造の必須子box重複・欠落・入れ子の不正値を検出。未知boxは保持し、known boxの必須項目は型付けする。
4. Duration/timescaleは整数のまま保持し、秒表示だけ有理数変換する。DTSとPTSを混同しない。
5. edit list（`elst`）はまずparse・保持までとし、demuxの時刻補正を上流がしない場合は勝手に加えない。

## 検証対象（What）
- [ ] moovにtrackが1/複数/0の正常・異常入力。
- [ ] mvhd/tkhd/mdhd v0/v1、timescale=0、各TrackKind、edit-list境界。
- [ ] 欠落mandatory box、重複box、非法なnested範囲で定義済みエラー。
- [ ] TrackInfoの時間がRust版と一致する。

## 完了条件
- [ ] 主要metadata型とテストを公開する。
- [ ] タイムスタンプの暗黙のfloat丸めがない。
- [ ] metadata表示デモに必要な情報を取得可能。

## 非対象・境界
字幕ペイロードの意味解析とeditsを使った再生時刻調整は非対象。
