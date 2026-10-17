# 互換性 matrix

状態は `Implemented` / `Partial` / `Not started` / `Blocked`。検証状態
（PASS / FAIL / UNVERIFIED / NOT_RUN）は独立して記録する。固定上流参照は
[`upstream.md`](./upstream.md) の SHA。

| 機能 | 状態 | 検証 | Issue |
| --- | --- | --- | --- |
| MP4/fMP4 kind 検出 | Implemented | Unit / oracle / fixture PASS | 0012 |
| 通常 MP4 demux | Implemented | Unit / oracle / fixture PASS | 0013 |
| Native demux CLI | Implemented | CLI smoke PASS | 0014 |
| Web Dump | Implemented | Node smoke PASS、Browser E2E は実環境依存 | 0015 |
| Rust/WASM diff lab | Implemented | Node runner PASS、browser E2E は実環境依存 | 0016 |
| fMP4 boxes | Implemented | Unit / roundtrip PASS、Rust oracle UNVERIFIED | 0017 |
| fMP4 segment demux | Implemented | Unit / roundtrip PASS、Rust oracle UNVERIFIED | 0018 |
| fMP4 file demux | Implemented | Unit / roundtrip PASS、Rust oracle UNVERIFIED | 0019 |
| fMP4 segment mux | Implemented | Unit / roundtrip PASS、Rust oracle UNVERIFIED | 0020 |
| fMP4 example | Implemented | Native manual run PASS | 0021 |
| 通常 MP4 mux | Implemented | Unit / roundtrip PASS、Rust interop UNVERIFIED | 0022 |
| MP4 mux example | Implemented | Native manual run PASS | 0023 |
| AVC/HEVC bitstream | Implemented | Unit PASS、Rust oracle UNVERIFIED | 0024 |
| AAC/Opus bitstream | Implemented | Unit PASS、Rust oracle UNVERIFIED | 0025 |
| AV1/VP8/VP9 bitstream | Implemented | Unit PASS、Rust oracle UNVERIFIED | 0026 |
| Hybrid MP4 positions | Implemented | Unit PASS、実ファイル E2E は未実行 | 0027 |
| 字幕 sample entry | Implemented | Unit / roundtrip PASS | 0028 |
| WebCodecs transcode | Not started / Partial | NOT_RUN | 0029 |
| Native gpui Inspector | Not started / Partial | NOT_RUN | 0030 |
| fuzz / PBT | Partial | fast mutation suite PASS、長時間 fuzz NOT_RUN | 0031 |
| 性能 baseline | Partial | read/I/O 回数の smoke のみ、時間・RSS NOT_RUN | 0032 |
| 公開文書 | Implemented | 本 PR | 0033 |
| 上流追従監査 | Partial | 手順・テンプレート、リハーサル未実行 | 0034 |

- 「Partial」は実装または検証の一部が未完了であることを示す。未実行を PASS と
  して扱わない。
- C ABI / 上流 WASM バインディング / 動画 decode・encode 本体は対象外。
