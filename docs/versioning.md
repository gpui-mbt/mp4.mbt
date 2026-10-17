# Versioning

- バージョンは `moon.mod` の `version` を一次情報とする。
- マイルストーンに応じた minor 進行の目安: v0.1 M0–M1、v0.2 M2、v0.3 M3、
  v0.4 M4、v0.5 M5。
- リリースタグと git SHA の対応は [`release-checklist.md`](./release-checklist.md)
  の手順で記録する。
- 上流参照 SHA はバージョンとは独立して固定し、[`upstream.md`](./upstream.md) と
  oracle の `Cargo.toml` / `UPSTREAM_SHA` を同時に更新する。
