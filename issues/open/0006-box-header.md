# 0006: BoxHeader・BoxSize・FourCC・uuidを実装する

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M1 MP4読取
- 依存Issue: `0005`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`（`develop` の調査時HEAD）

## 目的
8byteから始まるISO BMFF box envelopeを、size=1/0やuuidを含めて正しく区切れるようにする。

## 上流参照
- [src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs)
- [tests/test_basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_basic_types.rs)
- [tests/test_boxes.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes.rs)

## 実装手順（How）
1. 通常size32/large size64/size==0（トップレベルEOFまで）を区別し、`uuid`拡張16byte型を含むheader長を定義する。
2. sizeはheader自身を含む総長として保持。ヘッダが宣言した全体が取得範囲内にないときはNeedMoreとInvalidを区別する。
3. トップレベルと入れ子でsize==0の受理ポリシーを分ける。上流`UnknownBox::decode_top_level`の挙動も別Issueで扱う。
4. unknown FourCCは生4byteのまま保持し、制御文字や非UTF8を文字列変換で失わない。
5. Encodeは長さを選択して出力し、decoder→encoderのcanonical形式とwire-preserving形式を混同しない。

## 検証対象（What）
- [ ] size=8、size=1+largesize、size=0、uuidの正/負例の表形式ケース。
- [ ] size<header、size=1だが8byte不足、入れ子size=0、overflowの失敗種類。
- [ ] 未知の4CC・0byte payload・large-size境界でのRustとの差分。

## 完了条件
- [ ] BoxHeader単体のencode/decodeテストが全targetで成功。
- [ ] 不正長から過大allocationしない。
- [ ] BoxHeaderErrorに位置とbox型を残せる。

## 非対象・境界
moov構造やcodec固有の意味解析はここで実装しない。
