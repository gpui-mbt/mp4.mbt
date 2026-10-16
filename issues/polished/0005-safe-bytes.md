# [P0 / M1] Bounds-safeなバイト列・ビット列・エラー型を作る

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0005-safe-bytes
Priority: P0
Milestone: M1
Depends on: [0002](./0002-moonbit-bootstrap.md), [0004](./0004-oracle-fixtures.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

MP4の大半は信頼できない長さ付きbinary入力であり、整数overflowや境界外参照を統一して防ぐ土台が必要である。Big Endianのread/writeカーソル、bit reader/writer、失敗分類、`ParseLimits`を先に用意し、後続のbox解析がI/Oに依存しない純粋APIを使えるようにする。

## 背景

- 上流は [src/codec.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/codec.rs) のread/write codec、[src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs) の基本型、[src/bitstream.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream.rs) のbitstream処理として長さ付き入力を共通化している。本issueはこの土台のMoonBit移植である。
- 現時点の`mp4.mbt`はREADMEと`issues/`のみで、`moon.mod`もpackageもない。実装・テストは未着手であり、[0000](./0000-implementation-roadmap.md)は未実行のコマンドをPASSと扱わないことを定めている。
- package候補名は`src/bytes`・`src/bitstream`（[0000](./0000-implementation-roadmap.md)の提案パッケージ）。実際の`moon.pkg`分割と公開名は[0002](./0002-moonbit-bootstrap.md)で循環依存とtarget制約を検証してから確定する。
- 期待値の正しさは[0004](./0004-oracle-fixtures.md)のRust oracle・goldenで判定し、差分の表示は[0016](./0016-rust-moonbit-diff.md)が担当する。

## 問題

- byte/bitカーソルが未実装のため、box解析ごとに長さ検査と位置更新が重複すると、失敗時に中途半端な位置が残る危険がある。
- `offset + size`を直接計算すると整数overflowで境界検査を回避され得る。u64からJSのNumberやNativeのindexへの変換境界も未定義である。
- 失敗をInvalidInput/InvalidData/Unsupported等に分類し、box type・byte offset・理由を保持する共通エラー型がない。
- 巨大入力に対するallocationとnestingの制限がなく、宣言された長さを信じた過大確保や無限loopを防ぐ規則がまだ決まっていない。

## 目標

- read/writeカーソルがBig Endian u8/16/24/32/64、signed値、FourCC、固定小数、範囲付きslice取得、必要容量の判定を提供し、位置更新は成功後にのみ行う。
- checked arithmeticで計算し、u64からJSのNumberやNativeのindexへの変換境界を明文化する。
- bit reader/writerがMSB順、skip、固定幅の読み・書き、bit幅上限、終端チェックを提供し、後続のNAL/AAC/AV1で共用できる。
- 上流`ErrorKind`のInvalidInput/InvalidData/Unsupported等に対応する失敗分類とbox type／byte offset／理由を保持し、ユーザー入力のためにpanicしない。
- 巨大入力でのallocationとnestingを制限する`ParseLimits`をcoreに設け、既定値／上限変更と未取得rangeの扱いを記録する。
- 公開APIはI/Oに依存せず、JS/Nativeで同じ値と同じエラー分類を返す。

## 対象外

- ByteArray／Bytesの実装方法はターゲット制約を計測して選ぶ。本issueでは抽象と境界までを対象とし、表現形式の確定は計測後とする。
- 動画像のdecoded pixel bufferなど、codecとしてのpayload解釈は対象外。
- NAL/AAC/AV1の意味解析そのものはM4の[0024](./0024-bitstream-h264-h265.md)〜[0026](./0026-bitstream-av1-vp8-vp9.md)で扱い、本issueは共通プリミティブまでとする。

## 提案する方針

- 候補package`src/bytes`と`src/bitstream`に、read cursor/write cursorを定義する。Big Endian u8/16/24/32/64、signed値、FourCC、固定小数、範囲付きslice取得、必要容量を提供し、すべて位置更新を成功後に行う。失敗時には不完全な状態を残さない。
- `offset + size`は直接使わずchecked arithmeticにする。u64からJSのNumberやNativeのindexへ変換する境界を関数として明示し、`2^53`超を不正に丸めない。
- bit reader/writerはMSB順、skip、固定幅の読み・書き、bit幅上限、終端チェックを実装し、後続のNAL/AAC/AV1 helperが共有する。
- エラー型は上流`ErrorKind`のInvalidInput/InvalidData/Unsupported等に対応する分類を持ち、box type／byte offset／理由を保持する。ユーザー入力に対してpanicしない。
- `ParseLimits`をcoreに置き、巨大入力でのallocationとnestingを制限する。既定値、上限変更の方法、未取得rangeの扱いをテストとドキュメントに記録する。
- 互換性要件: 成功時の読み書きはJS/Nativeで同一値、失敗時は同一のエラー分類と位置情報を返す。[0004](./0004-oracle-fixtures.md)の差分比較では値だけでなく失敗分類まで比較する。
- 境界条件: zero-length、必要量に満たないbuffer、offset overflow、符号伸長、u64最大、`2^53`境界、符号付きCTTS相当の負値、最大値以上の確保要求をテスト表に含める。
- ファイル名・公開API名・`ParseLimits`の既定値は実装時に確定し、確定内容を本issueへ追記する。

## 受け入れ条件

- [ ] Given zero-lengthまたは短いbuffer, when BE read/writeを行う, then 失敗後の位置更新は進まず、不完全な状態が残らない。
- [ ] Given u64最大や`2^53`境界を含む列, when JS/Nativeで読み書きする, then 同じ値が得られ、暗黙の丸めが起きない。
- [ ] Given `offset + size`が整数overflowする列, when cursorの読み書きを要求する, then panicせず定義済みエラーで失敗する。
- [ ] Given 未取得rangeまたは容量不足, when slice取得を要求する, then 定義した必要容量と分類で失敗し、過大allocationしない。
- [ ] Given 不正なユーザー入力, when parseする, then panicしない。
- [ ] Given 符号付き値（CTTS相当の負値を含む）, when 読み書きする, then 符号伸長と固定小数の扱いが定義どおりで、JS/Nativeで一致する。
- [ ] Given 同じ入力, when JSとNativeでテストする, then 値とエラー分類が一致する。
- [ ] Given `moon info`で生成した公開API, when 差分を確認する, then 公開APIがI/Oに依存しない。

## テスト計画

- 本issueのコマンドは現時点で未実行とする。`moon.mod`とpackageがまだ無いため、実行できない確認をPASSと記録しない。結果はPASS / FAIL / 未実行を独立に記録する（[0000](./0000-implementation-roadmap.md)の検証状態区分）。
- 将来実行するコマンド: `moon check`、`moon fmt`の差分チェック、`moon info`、`moon test --target native`、`moon test --target js`。実行時はコマンド・target・commit SHA・日時を証跡に残す。
- Unit（whitebox）テスト: BE read/writeの固定パターンとzero-length／短いbufferでの正確な位置保持。u64最大・`2^53`境界・符号付きCTTS・負数相当を混ぜた境界入力。cursor offset overflow、符号伸長、最大値以上の確保をエラーとして検出。テスト名が何を検証するか分かるようにし、正常/異常の両方の例を置く。
- Differential: [0004](./0004-oracle-fixtures.md)の固定fixtureとoracleを使い、値とエラー分類をRustと比較する。
- 手動確認: なし（純粋関数のため、自動テストと差分比較で判定する）。JS/Nativeでの実行は[0003](./0003-ci-contract.md)のtarget別ジョブで確認する。

## リスク

- JSの数値精度: u64をNumberへ暗黙変換すると`2^53`超で丸まる。整数は意図した境界まで整数のまま扱い、JSON比較は十進文字列を使う（[0000](./0000-implementation-roadmap.md)のデータ契約6）。
- 表現方式のターゲット差: ターゲットごとにByteArray／Bytesの方式が分かれると挙動が分岐する。計測で方式を選び、同じ値・同じエラー分類を全targetテストで固定する。
- 境界検査の誤り: 入力不足と不正値の分類を混同すると、ストリーム読み取り側の再要求判断が壊れる。両方をUnitテストで固定する。
- limitsの厳しすぎ: 正しい巨大ファイルを拒否し得る。既定値を記録し、上限変更をAPIで可能にする。性能影響は[0032](./0032-performance-profile.md)で実測するまで主張しない。
- ロールバック: 新規packageの追加が中心で既存APIへの影響はない。問題時は該当commitのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] Bounds-safeなbyte/bitカーソル、エラー分類、ParseLimitsを追加

## 注記

- upstreamの対応物: [src/codec.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/codec.rs)、[src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs)、[src/bitstream.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream.rs)。
- 関連: [0002](./0002-moonbit-bootstrap.md)（package分割）、[0004](./0004-oracle-fixtures.md)（oracle）、[0006](./0006-box-header.md)（最初の利用側）、[0016](./0016-rust-moonbit-diff.md)（差分表示）、[0024](./0024-bitstream-h264-h265.md)〜[0026](./0026-bitstream-av1-vp8-vp9.md)（bitstreamの後続利用）、[0031](./0031-fuzz-pbt-hardening.md)（fuzz/PBT）。
- 証跡ルール: checkboxは実際に実行した証拠がある項目だけ完了にする。実行コマンド・target・commit SHA・fixture checksum・PASS/FAIL/未実行の区分を残す（[0000](./0000-implementation-roadmap.md)と[0003](./0003-ci-contract.md)に整合）。
- 実装時の未決事項: package名、カーソル型とエラー型の公開名、`ParseLimits`の既定値、ByteArray／Bytesの表現選定（計測後に確定）。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
