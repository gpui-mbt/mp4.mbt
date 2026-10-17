# Release checklist

実際の `moon publish`・タグ作成・GitHub Release は明示承認があるまで行わない。

## 必須コマンド

```bash
moon check --target native
moon check --target js
moon test --target native
moon test --target js
moon fmt --check
moon info && git diff --exit-code -- '*.mbti'
```

結果には commit SHA、OS/arch、MoonBit 版、実行日を付ける。失敗または未実行は
PASS と記録しない。

## Rust oracle

```bash
cd tools/oracle && cargo test && cd ../..
moon run tools/oracle/regenerate_fixtures.mbtx -- --check
```

pinned SHA は [`upstream.md`](./upstream.md) を参照。oracle が実行できない場合は
UNVERIFIED と記録する。

## Web / examples

```bash
sh web/build.sh
node web/run_lab.mjs
moon run src/examples/demux --target native -- <fixture>
moon run src/examples/fmp4 --target native -- <fixture> /tmp/fmp4-out
moon run src/examples/mux --target native -- <fixture> /tmp/out.mp4
PLAYWRIGHT_PATH=<dir> CHANNEL=chrome node web/e2e/transcode.mjs
```

## version / tag

- `moon.mod` の version とタグ名を一致させる。
- タグが指す git SHA を記録し、source と一致することを確認する。
- fixtures の SHA256 は `tests/fixtures/manifest.json` と一致させる。
- 未検証の target は [`compatibility.md`](./compatibility.md) で UNVERIFIED と表示する。

## 文書

- README の status と互換性 matrix を更新する。
- `CHANGES.md` の `Unreleased` を release version へ移す。
- NOTICE / LICENSE / fixture 帰属を確認する。
