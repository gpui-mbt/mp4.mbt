# [P0 / M1] BoxHeader・BoxSize・FourCC・uuidを実装する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0006-box-header
Priority: P0
Milestone: M1
Depends on: [0005](./0005-safe-bytes.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

8byteから始まるISO BMFFのbox envelopeを、size=1（largesize64）・size==0（EOFまで）・`uuid`拡張16byte型を含めて正しく区切れるようにする。BoxHeader単体のdecode/encodeと失敗分類を[0005](./0005-safe-bytes.md)のカーソル上に実装し、以降のbox tree・top-level走査・demuxの入力境界の基準にする。

## 背景

- 上流は [src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs) でbox headerとFourCC・uuid型を定義し、[tests/test_basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_basic_types.rs) と [tests/test_boxes.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes.rs) が境界ケースを固定している。本issueはこの移植である。
- 前提として[0005](./0005-safe-bytes.md)のread cursor、checked arithmetic、エラー分類が必要になる。
- 消費側は[0007](./0007-root-box-tree.md)のbox tree、[0012](./0012-file-kind-detector.md)のtop-level走査、[0013](./0013-mp4-file-demux.md)のdemuxであり、header判定の誤りは全解析のoffsetに波及する。
- 未実装状態: `mp4.mbt`はREADMEと`issues/`だけで、`moon.mod`もpackageもない。本issueの実行済みテストは存在するとは扱わない（[0000](./0000-implementation-roadmap.md)）。

## 問題

- size32・large size64・size==0の3形態と`uuid`拡張のheader長を区別しないと、box境界がずれて後続の全解析が壊れる。
- 宣言された総長が取得範囲内にない場合に、追加入力で retry できる不足と、長さとして成立しない不正を区別する規則がない。
- トップレベルと入れ子のsize==0受理ポリシー（EOFまでと不正の区別）が定まっていない。
- unknown FourCCを文字列化すると、制御文字や非UTF8の4byteが失われ得る。
- decoder→encoderのcanonical形式とwire-preserving形式を混同すると、正当化できないサイズ変更やbyte差分が生じる。

## 目標

- 通常size32／large size64／size==0（トップレベルEOFまで）を区別し、`uuid`拡張16byte型を含むheader長を定義する。
- sizeはheader自身を含む総長として保持する。ヘッダが宣言した全体が取得範囲内にないときは、入力不足と不正を区別する。
- トップレベルと入れ子でsize==0の受理ポリシーを分ける。上流`UnknownBox::decode_top_level`の挙動は別Issue（[0007](./0007-root-box-tree.md)）で扱う。
- unknown FourCCは生4byteのまま保持し、制御文字や非UTF8を文字列変換で失わない。
- encodeは長さ形式を選択して出力し、decoder→encoderのcanonical形式とwire-preserving形式を混同しない。
- 不正長から過大allocationせず、失敗時は位置とbox型を残せるエラーを返す。

## 対象外

- moov構造やcodec固有の意味解析はここで実装しない（[0008](./0008-movie-track-boxes.md)以降）。
- 木構造の走査とvisitor制限は[0007](./0007-root-box-tree.md)で扱う。本issueは単一headerの区切りまでとする。
- `mdat` payloadのrange表現・保持方針は[0007](./0007-root-box-tree.md)の範囲。

## 提案する方針

- 候補package`src/box`（[0000](./0000-implementation-roadmap.md)の提案パッケージ）にBoxHeader・BoxSize・FourCC・uuid型を実装する。実際の`moon.pkg`分割と公開名は[0002](./0002-moonbit-bootstrap.md)で確定する。
- 通常size32／large size64／size==0を区別し、`uuid`拡張16byte型を含むheader長を定義する。large sizeの64bit値は[0005](./0005-safe-bytes.md)のchecked arithmeticで範囲検査する。
- unknown FourCCは生4byteのまま保持し、制御文字や非UTF8を文字列変換して失わない。
- encodeは出力に合う長さ形式（size32／largesize）を選択する。decoder→encoderのcanonical形式と、入力のワイヤ表現を保つwire-preserving形式をAPIで区別し、混同しない。
- size==0の受理はトップレベルと入れ子で分ける。トップレベルではEOFまでの可変長として扱い得るが、入れ子では不正とする。上流`UnknownBox::decode_top_level`の詳細は[0007](./0007-root-box-tree.md)で移植する。
- 互換性要件: [0004](./0004-oracle-fixtures.md)の固定fixtureとoracleで、未知4CC・0byte payload・large-size境界の差分を取り、成否と失敗種類をRustと一致させる。
- 境界条件: size=8（payload 0byte）、size=1+largesize、size=0、uuidの正/負例、size<header、size=1で8byte不足、入れ子size==0、offset overflowを表形式のUnitテストに固定する。
- ファイル名・公開API名・BoxSizeの表現（enumか値か）は実装時に確定し、確定内容を本issueへ追記する。

## 受け入れ条件

- [ ] Given payload 0byte（size=8）のbox, when decodeしてencodeする, then header長4+4で正しく区切られ、canonical形式で同一bytesを再構成できる。
- [ ] Given size=1 + largesizeのbox, when decodeする, then 64bit総長が使われ、header長が総長に含まれる。
- [ ] Given トップレベルのsize==0, when 末尾までを入力する, then 可変長として区切られる。
- [ ] Given 入れ子のsize==0, when decodeする, then 不正として拒否される。
- [ ] Given uuid拡張のbox, when decodeしてencodeする, then 16byte型が保持され、再encodeで失われない。
- [ ] Given 宣言総長が取得範囲を超える入力, when decodeする, then 入力不足として追加入力で解消可能なエラーになる。
- [ ] Given sizeがheader長未満またはsize=1で8byte不足の入力, when decodeする, then 不正として入力不足と区別される。
- [ ] Given 未知FourCC（制御文字・非UTF8を含む）, when decodeしてencodeする, then 生4byteが失われない。
- [ ] Given Rust oracleと同じ表形式ケース, when 差分を取る, then 成否と失敗種類が一致する。
- [ ] Given 不正長の入力, when decodeする, then 過大allocationせず、エラーに位置とbox型が残る。
- [ ] Given BoxHeader単体のencode/decodeテスト, when 対応target（Native/JS）で実行する, then 全targetで成功する。

## テスト計画

- `moon.mod`とpackageがまだ無いため、本issueの確認は現時点で未実行とする。PASS / FAIL / 未実行を独立に記録し、実行できない確認をPASSと書かない（[0000](./0000-implementation-roadmap.md)）。
- 将来実行するコマンド: `moon check`、`moon fmt`の差分チェック、`moon info`、`moon test --target native`、`moon test --target js`。実行時はtarget・commit SHA・fixture checksum・日時を証跡に残す。
- Unit（whitebox）テスト: size=8、size=1+largesize、size=0、uuidの正/負例の表形式ケース。size<header、size=1で8byte不足、入れ子size==0、overflowの失敗種類。未知4CC・0byte payload・large-size境界。canonicalのdecode→encode往復とwire-preservingの区別。
- Differential: [0004](./0004-oracle-fixtures.md)のoracleで上記境界ケースのRustとの差分を取る。
- 全target: BoxHeader単体のテストをNative/JSで成功させる。WASM/WASM-GCは[0002](./0002-moonbit-bootstrap.md)のツールチェーン検証後にCIへ追加する。
- 手動確認: なし（本issue単体ではUIを持たない）。表示上の確認は[0015](./0015-web-mp4-dump.md)以降で行う。

## リスク

- size==0の扱い: トップレベル受理/入れ子拒否の判断を誤ると、box treeが無限loopや誤境界に陥る。境界ケースを表形式で固定する。
- 総長とheader長の混同: sizeはheader自身を含む総長であり、誤ると後続のoffsetが全面的にずれる。[0013](./0013-mp4-file-demux.md)のsample offsetにも波及するためUnitテストで固定する。
- wire-preservingの予期しない変更: size==0やlargesizeを再encodeで別形式に書き換えるとbyteが変わる。canonicalとwire-preservingをAPIで分離し、既定の挙動を明記する。
- FourCCの文字列変換: 制御文字・非UTF8をlossy変換するとbox type判定が壊れる。生4byte保持をテストで固定する。
- 過大allocation: 宣言長を信じた確保をしない。上限は[0005](./0005-safe-bytes.md)の`ParseLimits`に従う。
- ロールバック: 新規packageの追加が中心。問題時は該当commitのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] BoxHeader・BoxSize・FourCC・uuidのdecode/encodeを追加

## 注記

- upstreamの対応物: [src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs)、[tests/test_basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_basic_types.rs)、[tests/test_boxes.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes.rs)。
- 関連: [0005](./0005-safe-bytes.md)（カーソルとエラー）、[0007](./0007-root-box-tree.md)（最初の木構造と`UnknownBox::decode_top_level`）、[0012](./0012-file-kind-detector.md) / [0013](./0013-mp4-file-demux.md)（top-level走査とdemux）。
- 証跡ルール: checkboxは実際に実行した証拠がある項目だけ完了にする。実行コマンド・target・commit SHA・fixture checksum・PASS/FAIL/未実行の区分を残す（[0000](./0000-implementation-roadmap.md)と[0003](./0003-ci-contract.md)に整合）。
- 実装時の未決事項: BoxSizeの表現、canonical/wire-preservingを分けるAPIの形、公開名。確定後は本issueへ追記する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
