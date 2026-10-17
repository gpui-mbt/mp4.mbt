# [P0 / M1] stblとSampleTableAccessorを移植する

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
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

- [x] Given sample数1/複数と複数chunk, when accessorで走査する, then sample indexからfile offset・size・DTSが定義どおりに復元される。
- [x] Given `stsz`固定/可変, when parseする, then 各sample sizeが正しく返る。
- [x] Given `ctts`version 1の負値, when PTSを計算する, then PTS=DTS+CTTSが符号付きで正しく、DTSと混同しない。
- [x] Given CTTS未設定, when accessorで読む, then 未設定と0が区別される。
- [x] Given `co64`で2^32超のoffset, when 読む, then 64bit値が丸められない。
- [x] Given `stss`欠落, when sync判定する, then 全sampleがsync扱いになる。
- [x] Given `stsc`欠落・逆順・sample_count不整合・総duration overflow, when parseする, then 不正入力として定義済みエラーになる。
- [x] Given offset超過・非単調テーブル・index跨ぎ, when accessorで読む, then 明示的に拒否される。
- [x] Given 反復で全sampleを走査する, when accessorを使う, then 全sampleの巨大配列を最初から生成しない。
- [x] Given 複数track, when 並行して走査する, then trackごとのtimebaseと走査状態が独立に保持される。
- [x] Given 固定上流fixture, when sample offset/size/timestampをRust oracleと全件比較する, then 全件一致する。
- [x] Given 大きいテーブル, when 計算量とlimitsを確認する, then 文書化された範囲で扱える。

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
- 2026-10-17: stbl サブツリーと SampleTableAccessor の実装に着手（設計は /tmp/opencode/mp4mbt/tasks/0009-sample-tables.md に凍結済み）
- 2026-10-17: 実装（src/bytes・src/box）: `Either[A, B]`（`eq/hash/debug` 派生）と `src/box/either_base_box.mbt` の `pub impl[A : BaseBox, B : BaseBox] BaseBox for @bytes.Either[A, B]`。`pub extend @bytes.Either with BaseBox` は型とトレイトが別 package のためコンパイルエラー 4059 になり不可（3 つの generic impl で転送。`children()` は内側の子を返す。呼び出しは `@box.BaseBox::box_type(either)`。意図的な差として docs/upstream.md に記録）。
- 2026-10-17: 実装（src/boxes）: `stbl_box.mbt` / `stsd_box.mbt` / `sample_entry.mbt`（`Unknown(UnknownBox)` のみ。型付き variant は 0010）/ `stts_box.mbt`（`from_sample_deltas`、u32 overflow は `InvalidData "stts sample_count overflow"`）/ `ctts_box.mbt`（version 0/1 保持、負値・i32 超・不明 version のエラー文言は上流一致）/ `cslg_box.mbt` / `sdtp_box.mbt`（`SdtpSampleFlags`、version 0 のみ）/ `stsc_box.mbt` / `stsz_box.mbt`（`Fixed`/`Variable`）/ `stco_box.mbt`（`StcoBox` + `Co64Box`）/ `stss_box.mbt`。`StblBox` は必須 `stsd`/`stts`/`stsc`/`stsz`/`stco' or 'co64`（文言は上流一致）、重複は first-wins で `unknown_boxes` に保持、`stco` と `co64` が両方あるときは両方 decode してから `stco` を採用（`Either::A`、上流と同じ）。
- 2026-10-17: 実装（accessor）: `src/boxes/sample_table_accessor.mbt` に `SampleTableAccessor` / `SampleAccessor` / `ChunkAccessor` と `SampleTableAccessorError`（8 variant + `to_string`）。上流の `T: AsRef<StblBox>` と `AsRef` impl は移植せず、`StblBox` をコピー保持する値セマンティクス（意図的な差。docs/upstream.md に記録）。評価順・`UInt64` での overflow 検出・`chunk()` の `partition_point` - 1・`stss` なし=全 sync / 空=none sync・`ctts` なし `None` と 0 の区別・`get_sample_by_timestamp` の binary search は上流一致。`samples()`/`chunks()` は `Iter` を返し per-sample O(1)（prefix table は box の entry 数に比例するのみ）。`MinfBox::stbl_box` を追加して `stbl` を必須に戻し（欠落時 `InvalidData "Missing mandatory 'stbl' box in 'minf' box"`）、`MinfBox::new`・0008 の helper（`boxes_test_util_test.mbt`）と影響テストを更新。
- 2026-10-17: 証跡（unit）: `moon test --target native` 355/355 PASS、`moon test --target js` 355/355 PASS。新規テスト: 各 box の decode→encode round-trip と境界（ctts 8 件、cslg 5 件、sdtp 6 件、stbl 6 件、stsd 5 件、stts 4 件 + whitebox 2 件、stsc 4 件、stsz 5 件、stco/co64 5 件、stss 3 件）、accessor 22 件（1/複数 sample、複数 chunk、複数 stsc entry、空 chunk、固定/可変 stsz、co64 > 2^32、stco u32::MAX、stss あり/なし/空、ctts なし/0/負値、cslg・sdtp 保持、`get_sample_by_timestamp` の全域ヒットと範囲外 None、`get_sample`/`get_chunk` 範囲外 None、エラー全 8 variant とフィールド値、fixed/variable offset overflow、stts/ctts sample-count overflow、2 accessor の交互走査で track ごとの状態が独立、ゼロ件重複キーは決定的 leftmost）、oracle 差分 2 件。
- 2026-10-17: 証跡（differential）: `tools/oracle` に `sample-tables` / `sample-tables-cases` / `sample-tables-fixtures` を追加。固定ケース表 52 件（正常 24 + accessor error 13 + decode error 15。成功・accessor error は snapshot 行、decode error は `ok:false` + `error_kind`/`reason`、reason は oracle 非空時のみ比較）と全 9 fixture の track `stbl`（upstream で再 encode。例: black-h264-video.mp4 292 bytes、black-h265-video.mp4 3016 bytes、black-h264-fmp4.mp4 268 bytes）で全行一致。`cargo test` 19 件 PASS。`moon run tools/oracle/regenerate_fixtures.mbtx -- --check`: `fixtures: 9, unchanged: 9, written: 0, failures: 0`。
- 2026-10-17: 証跡（gate・生成物）: `moon check`（native/js）警告 0、`moon fmt --check` 差分なし、`moon info` 更新済み（`Either`、11 box 型、`SampleEntry`、`SdtpSampleFlags`、`SdtpBox`、accessor 3 型 + error、`MinfBox` の新シグネチャ）。生成物 `src/boxes/sample_table_oracle_cases_test.mbt`（md5 483f0bdd20123b4cc4a6b5a76c6c9ea3）/ `sample_table_oracle_fixtures_test.mbt`（md5 6add56ac697e46ddfcb8ead5fcc689d5）は再生成→`moon fmt` で md5 一致。0008 の生成物 5 ファイルも再生成後に byte 不変（moov-tree は 0008 記録の `7219ddd7d354497e46c27aee4d9b984f` / `b4715643cafc1ee401f146e2371a97b1` と一致）。`.github/workflows/ci.yml` の再生成 step・`git diff --exit-code` リスト・printf 件数を 2 ファイル追加に更新し、`docs/ci.md` / `tools/oracle/README.md` / `CHANGES.md` / `docs/upstream.md` / `docs/scope.md` を同一変更で更新。
- 2026-10-17: spec からの差分（理由つき）: (1) whole-file `sample-tables` の `input` は spec の `path` ではなく `name`/`size`/`sha256`（golden に絶対 path を入れない再現性ルール。0008 と同じ）、(2) `moov_error` キーを追加（moov 抽出・decode 失敗を空 `sample_tables` だけでなく明示）、(3) `stbl` decode 失敗は spec の `error=decode` snapshot 行ではなく 0008 と同じ `ok:false` + `error_kind`/`reason`（accessor error だけが snapshot 内の `error=accessor` 行）、(4) `Either` の `BaseBox` 転送は `pub extend` 不可のため `src/box` の generic impl 3 つ（呼び出しは `@box.BaseBox::box_type`）。いずれも `docs/upstream.md` / `tools/oracle/README.md` に記録。
- 2026-10-17: 実装・検証・ドキュメント・CI の全項目を完了し、done へ移行。
- 2026-10-17: 実装・全 gate・差分検証・ドキュメント更新を完了
