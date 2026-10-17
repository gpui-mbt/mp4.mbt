# 上流追従と互換性監査

固定参照 SHA を更新するときは、上流の変更と MoonBit 側の未実装・候補バグを
混同しない。次の手順を 1 つの PR で行う。

## 手順

1. `docs/upstream.md` の固定 SHA、`tools/oracle/Cargo.toml` の `rev`、
   `tools/oracle/src/main.rs` の `UPSTREAM_SHA` を同時に更新する。
2. 旧 SHA と新 SHA のソースをローカルへ用意し、次を実行する。

   ```bash
   python3 tools/upstream-drift/audit.py <old-src> <new-src> --json /tmp/drift.json
   ```

   出力の `source_diff` は上流ソースの変更、`contract_delta` は公開項目の差分である。
3. Rust oracle を新 SHA で再生成し、旧 baseline / 新 baseline / MoonBit candidate の
   三者比較を行う。ラベルは次の 4 種に分ける。
   - `upstream-spec-change`: 上流の仕様・実装変更
   - `moonbit-missing`: MoonBit 側の未実装
   - `candidate-bug`: MoonBit 側の候補バグ
   - `unverified`: oracle を取得できない
4. golden は自動上書きしない。元 fixture、SHA256、変更理由、oracle run ID、
   承認者を記録してから更新する。
5. `docs/compatibility.md` とリリース matrix の固定参照 SHA を更新する。
   上流 SHA が進んだだけでは「互換」と宣言しない。

## PR テンプレート

`.github/pull_request_template.md` に source diff / contract delta / fixture hash /
変更理由 / 承認の欄を用意している。空欄の baseline 更新は受け付けない。

## 監査リハーサル

2 つの一時ディレクトリに同じソースを置き、片方へ `pub fn audit_probe()` を追加して
`audit.py` を実行すると、`contract_delta.added` に差分が出る。oracle が利用できない
場合は `unverified` として記録し、一致扱いにしない。
