# [P0 / M1] stblとSampleTableAccessorを移植する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0009-sample-tables
Priority: P0
Milestone: M1
Depends on: [0008](./0008-movie-track-boxes.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

sample-to-chunkとtime-to-sampleからサンプル位置・再生時間を復元する核心である。`stbl`配下のtable群をparse/encodeし、sample indexからchunk/file offset・size・sample_description_index・DTS/duration/CTTS・sync flagsを返す`SampleTableAccessor`を実装する。ここが正しければ大部分の普通のMP4 demuxを実装できる。

## 背景

- 上流は [src/boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_moov_tree.rs) で`stbl`配下のtable群を、[src/auxiliary.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/auxiliary.rs) で`SampleTableAccessor`を定義している。[tests/test_boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_moov_tree.rs) と [fuzz/fuzz_targets/fuzz_sample_table_accessor.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_sample_table_accessor.rs) が期待値と堅牢性を固定している。本issueはこの移植である。
- 前提として[0008](./0008-movie-track-boxes.md)のTrackInfoと型付きmoov解析が必要になる。
- 消費側は[0010](./0010-sample-entries.md)（sample entryとの組み合わせ）、[0013](./0013-mp4-file-demux.md)、[0016](./0016-rust-moonbit-diff.md)であり、M3の[0022](./0022-mp4-file-mux.md)は逆方向にtableを構築する。
- 未実装状態: `mp4.mbt`はREADMEと`issues/`だけで、`moon.mod`もpackageもない（[0000](./0000-implementation-roadmap.md)）。

## 問題

- sample index→file offsetの復元（`stsc`×`stsz`×`stco`/`co64`）とtime-to-sample（`stts`）の実装がなく、demuxが成立しない。
- `ctts`のversion 0（unsigned）とversion 1（signed）、`co64`の64bit offset、`stss`欠落（全sync扱い）の区別が未定義である。
- `stsc`欠落・逆順、sample_count不整合、総duration overflowなどの不正テーブルを明示的に拒否する規則がない。
- 全sampleの巨大配列を最初から生成すると、大きなファイルでメモリを消費する。
- trackごとのtimebaseと走査状態の独立性が未定義である。

## 目標

- `stsd`/`stts`/`ctts`/`stsc`/`stsz`/`stco`/`co64`/`stss`/`sdtp`/`cslg`をparser/encoderに展開する。
- `SampleTableAccessor`にsample index→chunk/file offset・size・sample_description_index・DTS/duration/CTTS・sync flagsを返すAPIを用意する。
- `ctts`version 0 unsigned / version 1 signedと`co64`を扱い、offset超過や非単調テーブル・index跨ぎを明示的に拒否する。
- 反復中の位置取得はサンプル個数に対してO(n)を目指し、全sampleの巨大配列を最初から生成しない。
- trackごとに独立したtimebaseとサンプル走査状態を保持する。
- sample indexから実bytesの範囲を再現でき、巨大テーブルを扱うときの計算量とlimitsが文書化される。

## 対象外

- codec固有のNAL/OBUのデコードはしない（[0024](./0024-bitstream-h264-h265.md)〜[0026](./0026-bitstream-av1-vp8-vp9.md)）。
- sample entry本体とcodec情報は[0010](./0010-sample-entries.md)の範囲。字幕sample entryは[0028](./0028-subtitle-sample-entry.md)。
- 不正入力のfuzz/PBTによる網羅探索は[0031](./0031-fuzz-pbt-hardening.md)で行い、本issueは代表境界の回帰入力までとする。

## 提案する方針

- 候補package`src/boxes`（[0000](./0000-implementation-roadmap.md)の提案パッケージ）に`stbl`配下のbox群を、補助モジュールに`SampleTableAccessor`を置く。上流の`src/boxes_moov_tree.rs`と`src/auxiliary.rs`の分担に対応する。実際の`moon.pkg`分割と公開名は[0002](./0002-moonbit-bootstrap.md)で確定する。
- `stsd`/`stts`/`ctts`/`stsc`/`stsz`/`stco`/`co64`/`stss`/`sdtp`/`cslg`をparser/encoderに展開する。
- `SampleTableAccessor`にsample index→chunk/file offset・size・sample_description_index・DTS/duration/CTTS・sync flagsを返すAPIを用意する。走査状態はaccessor/iteratorに持たせ、呼び出し側が全sample配列を要求しない形にする。
- `ctts`version 0 unsigned / version 1 signedと`co64`を扱い、offset超過や非単調テーブル・index跨ぎを明示的に拒否する。
- 反復中の位置取得はサンプル個数に対してO(n)を目指し、全sampleの巨大配列を最初から生成しない。
- trackごとに独立したtimebaseとサンプル走査状態を保持する（[0008](./0008-movie-track-boxes.md)のTrackInfoと対応）。
- 互換性要件: [0004](./0004-oracle-fixtures.md)の固定上流fixtureでsample offset/size/timestampをRust oracleと全件比較する。CTTS未設定と0の区別、DTSとPTSの扱いは[0000](./0000-implementation-roadmap.md)のデータ契約1に従う。
- 境界条件: sample数1/複数、複数chunk、同じchunkの複数sample、`stsz`固定/可変、CTTS正負、`co64`>2^32、`stco`境界、`stss`欠落（全sync扱い）、`stsc`欠落・逆順・sample_count不整合・総duration overflow、index跨ぎをテスト表に置く。
- 上流のfuzz対象`fuzz_sample_table_accessor`を参照し、任意bytesでpanic/無限loopしないことの回帰化は[0031](./0031-fuzz-pbt-hardening.md)へ引き継ぐ。
- API名・iterator設計・limits既定値は実装時に確定し、確定内容を本issueへ追記する。

## 受け入れ条件

- [ ] Given sample数1/複数と複数chunk, when accessorで走査する, then sample indexからfile offset・size・DTSが定義どおりに復元される。
- [ ] Given `stsz`固定/可変, when parseする, then 各sample sizeが正しく返る。
- [ ] Given `ctts`version 1の負値, when PTSを計算する, then PTS=DTS+CTTSが符号付きで正しく、DTSと混同しない。
- [ ] Given CTTS未設定, when accessorで読む, then 未設定と0が区別される。
- [ ] Given `co64`で2^32超のoffset, when 読む, then 64bit値が丸められない。
- [ ] Given `stss`欠落, when sync判定する, then 全sampleがsync扱いになる。
- [ ] Given `stsc`欠落・逆順・sample_count不整合・総duration overflow, when parseする, then 不正入力として定義済みエラーになる。
- [ ] Given offset超過・非単調テーブル・index跨ぎ, when accessorで読む, then 明示的に拒否される。
- [ ] Given 反復で全sampleを走査する, when accessorを使う, then 全sampleの巨大配列を最初から生成しない。
- [ ] Given 複数track, when 並行して走査する, then trackごとのtimebaseと走査状態が独立に保持される。
- [ ] Given 固定上流fixture, when sample offset/size/timestampをRust oracleと全件比較する, then 全件一致する。
- [ ] Given 大きいテーブル, when 計算量とlimitsを確認する, then 文書化された範囲で扱える。

## テスト計画

- `moon.mod`とpackageがまだ無いため、本issueの確認は現時点で未実行とする。PASS / FAIL / 未実行を独立に記録し、実行できない確認をPASSと書かない（[0000](./0000-implementation-roadmap.md)）。
- 将来実行するコマンド: `moon check`、`moon fmt`の差分チェック、`moon info`、`moon test --target native`、`moon test --target js`。実行時はtarget・commit SHA・fixture checksum・日時を証跡に残す。
- Unit（whitebox）テスト: sample数1/複数、複数chunk、同じchunkの複数sample、`stsz`固定/可変、CTTS正負、`co64`>2^32、`stco`境界、`stss`欠落、`stsc`欠落・逆順・sample_count不整合・総duration overflowを表形式入力で固定する。
- Differential: [0004](./0004-oracle-fixtures.md)のfixed fixtureでsample offset/size/timestampをRust oracleと全件比較する。比較は正規化JSON（64bit整数は十進文字列）で行う。
- Fuzz/PBT: 上流`fuzz_sample_table_accessor`の考え方を[0031](./0031-fuzz-pbt-hardening.md)で回帰化する。本issueでは決定的な境界入力のUnitテストまでを対象とする。
- 手動確認: なし（本issue単体ではUIを持たない）。実データの表示は[0014](./0014-demux-example.md)のdemux exampleと[0015](./0015-web-mp4-dump.md)で確認する。
- 計算量: O(n)と保持量limitsの記述は実装時に確定する。実測値は[0032](./0032-performance-profile.md)まで主張しない。

## リスク

- off-by-one: `stsc`のfirst_chunk/samples_per_chunkと`stsz` indexの解釈を誤ると全sampleのoffsetがずれる。同じchunkに複数sampleがあるケースを必須テストにする。
- CTTS version: version判定を誤ると2^31超の値や負値が壊れる。version 0/1を分けたテストを置く。
- 64bitとJS精度: `co64`>2^32はNumberで丸め得る。整数のまま扱い、比較では十進文字列を使う（[0000](./0000-implementation-roadmap.md)のデータ契約6）。
- 不正テーブルの補正: 非単調・欠落を黙って補正するとRustとずれる。明示エラーにする。
- O(n)の定数因子: per-sampleの一時オブジェクト生成で重くなり得る。iterator設計に留め、実測は[0032](./0032-performance-profile.md)で行う。
- ロールバック: 新規実装が中心で成功パスの既存契約を変えない。問題時は該当commitのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] stbl配列のparser/encoderとSampleTableAccessorを追加

## 注記

- upstreamの対応物: [src/boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_moov_tree.rs)、[src/auxiliary.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/auxiliary.rs)、[tests/test_boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_moov_tree.rs)、[fuzz/fuzz_targets/fuzz_sample_table_accessor.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_sample_table_accessor.rs)。
- 関連: [0008](./0008-movie-track-boxes.md)（前提）、[0010](./0010-sample-entries.md) / [0013](./0013-mp4-file-demux.md) / [0016](./0016-rust-moonbit-diff.md)（消費者）、[0022](./0022-mp4-file-mux.md)（逆方向のtable構築）、[0024](./0024-bitstream-h264-h265.md)〜[0026](./0026-bitstream-av1-vp8-vp9.md)（非対象のcodecデコード）、[0031](./0031-fuzz-pbt-hardening.md) / [0032](./0032-performance-profile.md)（堅牢化と実測）。
- 証跡ルール: checkboxは実際に実行した証拠がある項目だけ完了にする。実行コマンド・target・commit SHA・fixture checksum・PASS/FAIL/未実行の区分を残す（[0000](./0000-implementation-roadmap.md)と[0003](./0003-ci-contract.md)に整合）。
- 実装時の未決事項: accessorの公開APIとiterator名、limits既定値、`stsd`エントリ型の受け渡し（[0010](./0010-sample-entries.md)との境界）。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
