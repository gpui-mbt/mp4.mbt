# 0007: ftyp・mdat・free・UnknownBoxとBox treeを実装する

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M1 MP4読取
- 依存Issue: `0006`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`（`develop` の調査時HEAD）

## 目的
box headerから表示可能なルート構造を得る。未知のboxも捨てず、合法でない深さ・長さは明示的に拒否する。

## 上流参照
- [src/boxes.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes.rs)
- [src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs)
- [tests/test_decode_encode.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_decode_encode.rs)

## 実装手順（How）
1. ftypのmajor_brand/minor_version/compatible_brandsを解析・生成する。`mdat`は原則payloadをcopyせずrangeとして表現する。
2. `free`/`skip`などのpaddingとUnknownBoxを扱い、未知top-levelは必要に応じてsize==0を末尾まで受理。入れ子でsize==0を認めない。
3. BoxNodeとして`type`、`start`、`header_bytes`、`declared_size`、`end`、`children`の観測情報を公開し、lazy payloadとsemantic typed boxを分離する。
4. `BoxTreeVisitor`に最大深さ・総node数・payload保持量の制限を設ける。
5. 再encode時にunknown payloadを保持するかどうかをAPIで明示し、表示専用のskipとwire-preservingを混同しない。

## 検証対象（What）
- [ ] ftyp + free + mdat の正しい境界とroot順序。
- [ ] unknown top-level可変長の受理・unknown nested可変長の拒否。
- [ ] ネスト過深/同じoffsetへのloop/親境界超過が安全にエラー。
- [ ] Rust側のBox treeと可視部分を比較。

## 完了条件
- [ ] box treeに位置・サイズ・FourCC・未解釈領域が出せる。
- [ ] 大型mdatを不必要に丸ごと保持しない。
- [ ] 異常データで無限ループしない。

## 非対象・境界
映像・音声サンプルデータの中身はdecodeしない。
