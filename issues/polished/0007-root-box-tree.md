# [P0 / M1] ftyp・mdat・free・UnknownBoxとBox treeを実装する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0007-root-box-tree
Priority: P0
Milestone: M1
Depends on: [0006](./0006-box-header.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

box headerから表示可能なルート構造を得る。未知のboxも捨てず、合法でない深さ・長さは明示的に拒否する。ftyp・mdat・free・UnknownBoxの列挙とBoxNodeの観測情報を[0006](./0006-box-header.md)のheader判定の上に実装し、moov以下やtop-level走査の共通入力にする。

## 背景

- 上流は [src/boxes.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes.rs) でbox列挙とUnknownBoxを、[src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs) で基本型を定義し、[tests/test_decode_encode.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_decode_encode.rs) がdecode/encodeの往復を固定している。本issueはこの移植である。
- 前提として[0006](./0006-box-header.md)のBoxHeader・BoxSize・FourCC・uuidが必要になる。
- 消費側は[0008](./0008-movie-track-boxes.md)のmoov以下、[0012](./0012-file-kind-detector.md)のmoov/mvex走査、[0013](./0013-mp4-file-demux.md)のdemux、[0015](./0015-web-mp4-dump.md)のDump表示、[0016](./0016-rust-moonbit-diff.md)のbox tree差分である。
- 未実装状態: `mp4.mbt`はREADMEと`issues/`だけで、`moon.mod`もpackageもない（[0000](./0000-implementation-roadmap.md)）。

## 問題

- top-level boxの順序と境界（ftyp／free／mdat／unknown）を安全に列挙する仕組みがない。
- `mdat`をcopyして保持すると、ファイルサイズに比例したメモリを消費する。
- 未知top-levelのsize==0（EOFまで）と、入れ子のsize==0を区別する受理ポリシーが未定義である。
- 深いnesting・同一offsetへのloop・親境界超過で、無限loopや過大保持が起き得る。
- 再encode時にunknown payloadを保持するか、表示専用に捨てるかの区別が未定義である。

## 目標

- ftypのmajor_brand／minor_version／compatible_brandsを解析・生成できる。
- `mdat`は原則payloadをcopyせずrangeとして表現する。
- `free`/`skip`などのpaddingとUnknownBoxを扱い、未知top-levelは必要に応じてsize==0を末尾まで受理する。入れ子でsize==0を認めない。
- BoxNodeとして`type`、`start`、`header_bytes`、`declared_size`、`end`、`children`の観測情報を公開し、lazy payloadとsemantic typed boxを分離する。
- `BoxTreeVisitor`の走査に最大深さ・総node数・payload保持量の制限を設ける。
- 再encode時にunknown payloadを保持するかどうかをAPIで明示し、表示専用のskipとwire-preservingを混同しない。
- 大型mdatを不必要に丸ごと保持せず、異常データで無限ループしない。box treeに位置・サイズ・FourCC・未解釈領域を出せる。

## 対象外

- 映像・音声サンプルデータの中身はdecodeしない。
- moov以下の意味解析は[0008](./0008-movie-track-boxes.md)で扱う。
- box header単体の境界とsize==0の区切りは[0006](./0006-box-header.md)の範囲。

## 提案する方針

- 候補package`src/boxes`（[0000](./0000-implementation-roadmap.md)の提案パッケージ）にBoxNode・box列挙・visitorを実装する。実際の`moon.pkg`分割と公開名は[0002](./0002-moonbit-bootstrap.md)で確定する。
- ftypのmajor_brand／minor_version／compatible_brandsを解析・生成する。`mdat`は原則payloadをcopyせずrangeとして表現し、保持するのは位置とサイズまでにする。
- `free`/`skip`などのpaddingとUnknownBoxを扱う。未知top-levelは必要に応じてsize==0を末尾まで受理し、入れ子でsize==0を認めない（[0006](./0006-box-header.md)のheader区分に対応）。
- BoxNodeとして`type`、`start`、`header_bytes`、`declared_size`、`end`、`children`の観測情報を公開する。lazy payloadとsemantic typed boxを分離し、表示が全体をmaterializeせずに済む形にする。
- `BoxTreeVisitor`に最大深さ・総node数・payload保持量の制限を設け、[0005](./0005-safe-bytes.md)の`ParseLimits`と接続する。上限の既定値は実装時に確定する。
- 再encode時にunknown payloadを保持するかどうかをAPIで明示する。表示専用のskipとwire-preservingを混同しない。
- 互換性要件: [0004](./0004-oracle-fixtures.md)のoracleで、Rust側のBox treeと可視部分（type・位置・サイズ・順序・未解釈領域）を比較する。[0012](./0012-file-kind-detector.md)／[0013](./0013-mp4-file-demux.md)／[0015](./0015-web-mp4-dump.md)／[0016](./0016-rust-moonbit-diff.md)は同じ観測情報を使う。
- 境界条件: ftyp+free+mdatの境界とroot順序、未知top-level可変長の受理、未知入れ子可変長の拒否、ネスト過深、同一offsetへのloop、親境界超過をテスト表に固定する。

## 受け入れ条件

- [ ] Given ftyp + free + mdat, when rootを列挙する, then 各boxの境界とroot順序が正しく、mdatのpayloadを保持しない。
- [ ] Given 未知top-levelのsize==0, when 末尾までを入力する, then 可変長として受理される。
- [ ] Given 未知入れ子boxのsize==0, when parseする, then 不正として拒否される。
- [ ] Given ネスト過深または同一offsetへのloop, when parseする, then 定義済みのlimitエラーで停止し、無限ループしない。
- [ ] Given 親境界を超える子box, when parseする, then 安全に定義済みエラーになる。
- [ ] Given box treeの表示, when dumpする, then 位置・サイズ・FourCC・未解釈領域が出せる。
- [ ] Given 大型mdatを含むfixture, when treeを構築する, then payloadを丸ごと保持しない。
- [ ] Given Rust oracleと同じfixture, when 可視部分を比較する, then box treeの観測項目が一致する。
- [ ] Given 再encode設定（unknown payload保持の有無）, when encodeする, then APIで明示した挙動どおりで、表示専用skipとwire-preservingが混同されない。

## テスト計画

- `moon.mod`とpackageがまだ無いため、本issueの確認は現時点で未実行とする。PASS / FAIL / 未実行を独立に記録し、実行できない確認をPASSと書かない（[0000](./0000-implementation-roadmap.md)）。
- 将来実行するコマンド: `moon check`、`moon fmt`の差分チェック、`moon info`、`moon test --target native`、`moon test --target js`。実行時はtarget・commit SHA・fixture checksum・日時を証跡に残す。
- Unit（whitebox）テスト: ftyp+free+mdatの正しい境界とroot順序。未知top-level可変長の受理・未知入れ子可変長の拒否。ネスト過深・同一offsetへのloop・親境界超過のエラー。lazy payloadでの保持量。encodeのcanonical/wire-preservingの差。
- Differential: [0004](./0004-oracle-fixtures.md)のoracleでRust側のBox treeと可視部分を比較する。64bit値は十進文字列で比較する（[0000](./0000-implementation-roadmap.md)のデータ契約6）。
- 手動確認: [0015](./0015-web-mp4-dump.md)のブラウザDumpでtree表示を目視確認する段階で行う。本issue単体では表示UIを作らない。
- 性能: 大型mdatのretained量は実測を[0032](./0032-performance-profile.md)まで主張せず、本issueではrange表現であることを型とテストで示す。

## リスク

- mdatのcopy: うっかりpayloadを保持するとメモリ使用量がファイルサイズ比例で膨らむ。range表現を型とテストで固定する。
- size==0のwire-preserving: 再encodeで明示長に書き換えるとbytesが変わる。canonical出力と入力保存をAPIで分離し、既定を明記する。
- visitor limits: 厳しすぎると正常な深いbox階層を拒否し、緩すぎると資源攻撃に弱い。既定値と変更方法を記録し、境界をテストする。
- unknown boxの扱い: 保持・表示・再encodeの規則がconsumerごとにばらつくとDumpが誤解を生む。観測情報の型を一本化する。
- ロールバック: 新規packageの追加が中心。問題時は該当commitのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] ftyp・mdat・free・UnknownBoxとBox tree走査を追加

## 注記

- upstreamの対応物: [src/boxes.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes.rs)、[src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs)、[tests/test_decode_encode.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_decode_encode.rs)。
- 関連: [0006](./0006-box-header.md)（前提）、[0008](./0008-movie-track-boxes.md)（moov以下）、[0012](./0012-file-kind-detector.md) / [0013](./0013-mp4-file-demux.md)（消費者）、[0015](./0015-web-mp4-dump.md)（表示）、[0016](./0016-rust-moonbit-diff.md)（差分）。
- 証跡ルール: checkboxは実際に実行した証拠がある項目だけ完了にする。実行コマンド・target・commit SHA・fixture checksum・PASS/FAIL/未実行の区分を残す（[0000](./0000-implementation-roadmap.md)と[0003](./0003-ci-contract.md)に整合）。
- 実装時の未決事項: visitorの名称、limit既定値、canonical/wire-preservingのAPI形、公開名。確定後は本issueへ追記する。
- 上流`UnknownBox::decode_top_level`のsize==0挙動は、本issueのtop-level走査として移植する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
