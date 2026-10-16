# 0027: faststartとHybrid MP4の書込位置契約を固める

- 状態: open（計画。未実装・未テスト）
- 優先度: P2
- フェーズ: M4 高度なMux
- 依存Issue: `0020`、`0022`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
正常終了後は通常MP4、途中停止でも確定fragmentが読めるHybrid MP4を実現できるwriter契約を用意する。

## 上流参照
- [docs/hybrid_mp4.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/docs/hybrid_mp4.md)
- [src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)
- [tests/test_mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_mp4_file.rs)

## 実装手順（How）
1. `Mp4FileMuxer::advance_position`相当で非サンプルbytesを書いた分の内部write位置を進め、次のsampleで必ず新chunkに切り替える。
2. Hybridの`moof/mdat`の生成は利用側（またはfMP4 muxer）と分離し、通常MP4 muxが最終`moov`を構築する。
3. finalize時には先頭の大きなmdatヘッダー書換・末尾moov配置等、caller側の実file操作を丁寧にサンプル化する。
4. faststart reserved_moov領域の不足、長さoverflow、位置不一致、途中落ち時点での有効なfragment境界を区別する。

## 検証対象（What）
- [ ] 上流のHybrid文書手順と同じcontent/offsetを得る。
- [ ] advance_positionなしの位置不一致が必ず検出される。
- [ ] 途中で止めたファイルは最後の確定segmentまで読める条件を明記して再生性を検証する。
- [ ] 正常finalize後は通常MP4 demuxと外部mediainfo/ffprobe相当で構造確認する。

## 完了条件
- [ ] Hybrid設計の責務分離とsampleが完成する。
- [ ] 途中停止・正常終了の両fixtureで実行証跡がある。

## 非対象・境界
OSのクラッシュ耐久性を完全に保証しない。fsync、書込順と電源断の保証は別途OS層の責務。
