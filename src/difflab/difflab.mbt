// Issue 0016: Rust/WASM (reference) と MoonBit/JS (candidate) の同一入力
// 差分レポート。双方の観測 JSON を field path 単位で突き合わせ、
// PASS / FAIL / UNVERIFIED / NOT_RUN を区別する。
//
// - oracle 側: tools/lab-oracle (wasm32) が出力する canonical schema
//   (`tools/oracle` の demux/box-tree emit と同一実装)。64bit は十進文字列。
// - candidate 側: src/webdump の `mp4dump_report_json` 出力。
// - 未知キーはゼロ埋めせず `excluded` に記録する (許可リスト方式)。
// - box tree は upstream の注意 (出現順が入力順と一致しない場合あり) に従い
//   順序非依存で比較し、順序差は `box_tree.order` エントリとして分離する。

///|
/// 差分エントリ 1 件分。
priv struct DiffEntry {
  path : String
  verdict : String
  expected : Json
  actual : Json
  note : String
}

///|
/// 比較結果の収集器。
priv struct DiffBuilder {
  entries : Array[DiffEntry]
  excluded : Array[Json]
}

///|
fn DiffBuilder::new() -> DiffBuilder {
  { entries: [], excluded: [], }
}

///|
fn DiffBuilder::entry(
  self : DiffBuilder,
  path : String,
  verdict : String,
  expected~ : Json = Json::null(),
  actual~ : Json = Json::null(),
  note~ : String = "",
) -> Unit {
  self.entries.push({ path, verdict, expected, actual, note, })
}

///|
fn DiffBuilder::pass(
  self : DiffBuilder,
  path : String,
  expected : Json,
) -> Unit {
  self.entry(path, "pass", expected~, actual=expected)
}

///|
fn DiffBuilder::fail(
  self : DiffBuilder,
  path : String,
  expected : Json,
  actual : Json,
  note~ : String = "",
) -> Unit {
  self.entry(path, "fail", expected~, actual~, note~)
}

///|
fn DiffBuilder::unverified(
  self : DiffBuilder,
  path : String,
  note : String,
) -> Unit {
  self.entry(path, "unverified", note~)
}

///|
fn DiffBuilder::excluded(
  self : DiffBuilder,
  path : String,
  reason : String,
) -> Unit {
  let obj : Map[String, Json] = Map([])
  obj["path"] = Json(path)
  obj["reason"] = Json(reason)
  self.excluded.push(Json::object(obj))
}

///|
/// Json 値を「十進整数文字列」に正規化する。
/// 文字列はそのまま、Number は repr (ソース表記) 優先、なければ Double から
/// 整数判定して十進化する。整数でない値・配列・オブジェクトは None。
fn decimal_repr(v : Json) -> String? {
  match v {
    String(s) => Some(s)
    Number(n, repr~) =>
      match repr {
        Some(r) => Some(r)
        None =>
          if n == n.trunc() &&
            n >= -9007199254740992.0 &&
            n <= 9007199254740992.0 {
            Some(n.to_int64().to_string())
          } else {
            Some(n.to_string())
          }
      }
    Null | True | False | Array(_) | Object(_) => None
  }
}

///|
/// Json 値を文字列として取り出す (String のみ)。
fn as_string(v : Json) -> String? {
  match v {
    String(s) => Some(s)
    _ => None
  }
}

///|
/// Json 値を Bool として取り出す。
fn as_bool(v : Json) -> Bool? {
  match v {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
/// オブジェクトのフィールドを取り出す。非オブジェクトは None。
fn field(v : Json, key : String) -> Json? {
  match v {
    Object(m) => m.get(key)
    _ => None
  }
}

///|
/// oracle/candidate 両方を正規化した上で 1 フィールド比較する。
/// `norm` は None 入力 (キー欠落 = null) も含めて canonical 文字列へ写す。
fn cmp_field(
  b : DiffBuilder,
  path : String,
  oracle : Json?,
  candidate : Json?,
  norm : (Json) -> String?,
) -> Unit {
  match (oracle, candidate) {
    (None, None) =>
      // 両側にキーが無い: 観測できなかったので比較不能ではなく一致扱い。
      b.pass(path, Json::null())
    (None, Some(_)) =>
      b.unverified(path, "oracle side missing field (schema drift)")
    (Some(_), None) =>
      b.unverified(path, "candidate side missing field (schema drift)")
    (Some(e), Some(a)) => {
      let ne = norm(e)
      let na = norm(a)
      match (ne, na) {
        (Some(x), Some(y)) =>
          if x == y {
            b.pass(path, Json(x))
          } else {
            b.fail(path, Json(x), Json(y))
          }
        (None, None) => b.pass(path, Json::null())
        _ =>
          b.fail(path, e, a, note="normalization mismatch (type/shape differs)")
      }
    }
  }
}

///|
/// 十進正規化 (64bit は文字列保持。数値も repr/整数化で十進文字列へ)。
fn norm_decimal(v : Json) -> String? {
  match decimal_repr(v) {
    Some(_) as s => s
    None =>
      match v {
        Null => Some("<null>")
        _ => None
      }
  }
}

///|
/// null 許容の十進正規化 (CTTS の None と 0 を区別するため null は "null")。
fn norm_decimal_nullable(v : Json) -> String? {
  match v {
    Null => Some("<null>")
    _ => decimal_repr(v)
  }
}

///|
/// 文字列正規化。
fn norm_string(v : Json) -> String? {
  as_string(v)
}

///|
/// null 許容の文字列正規化。
fn norm_string_nullable(v : Json) -> String? {
  match v {
    Null => Some("<null>")
    _ => as_string(v)
  }
}

///|
/// Bool 正規化。
fn norm_bool(v : Json) -> String? {
  match as_bool(v) {
    Some(true) => Some("true")
    Some(false) => Some("false")
    None => None
  }
}

///|
/// kind 値の正規化。oracle は "mp4" / "fragmented-mp4"、
/// candidate は "normal" / "fragmented"。canonical は oracle 側の表記に揃える。
fn norm_kind(v : Json) -> String? {
  match as_string(v) {
    Some("mp4") | Some("normal") => Some("mp4")
    Some("fragmented-mp4") | Some("fragmented") => Some("fragmented-mp4")
    Some(other) => Some(other)
    None => None
  }
}

///|
/// エラー分類の正規化。candidate の PascalCase (`InvalidData`) と
/// oracle の snake_case (`invalid_data` / `decode_error`) を canonical の
/// snake_case に揃える。
fn norm_error_kind(v : Json) -> String? {
  match as_string(v) {
    Some(s) => {
      let buf = StringBuilder()
      for c in s {
        if c >= 'A' && c <= 'Z' {
          if !buf.to_string().is_empty() {
            buf.write_char('_')
          }
          buf.write_char(c.to_ascii_lowercase())
        } else {
          buf.write_char(c)
        }
      }
      Some(buf.to_string())
    }
    None => None
  }
}

///|
/// sample_entry / 4CC の正規化 (null 許容)。
fn norm_fourcc(v : Json) -> String? {
  norm_string_nullable(v)
}

///|
/// oracle tracks.items と candidate tracks の要素比較。
fn compare_tracks(b : DiffBuilder, oracle : Json?, candidate : Json?) -> Unit {
  let o_items = match oracle {
    Some(o) =>
      match field(o, "status") {
        Some(String("ok")) =>
          match field(o, "items") {
            Some(Array(items)) => Some(items)
            _ => None
          }
        Some(String(s)) => {
          b.unverified("tracks", "oracle status: \{s}")
          return
        }
        _ => {
          b.unverified("tracks", "oracle tracks missing status")
          return
        }
      }
    None => {
      b.unverified("tracks", "oracle report missing tracks")
      return
    }
  }
  let c_items = match candidate {
    Some(Array(items)) => Some(items)
    _ => None
  }
  match (o_items, c_items) {
    (Some(o), Some(c)) => {
      // 個数
      if o.length() == c.length() {
        b.pass("tracks.count", Json::number(o.length().to_double()))
      } else {
        b.fail(
          "tracks.count",
          Json::number(o.length().to_double()),
          Json::number(c.length().to_double()),
        )
      }
      let n = if o.length() < c.length() { o.length() } else { c.length() }
      for i in 0..<n {
        let oi = o[i]
        let ci = c[i]
        let base = "tracks[\{i}]"
        cmp_field(
          b,
          "\{base}.track_id",
          field(oi, "track_id"),
          field(ci, "track_id"),
          norm_decimal,
        )
        cmp_field(
          b,
          "\{base}.kind",
          field(oi, "kind"),
          field(ci, "kind"),
          norm_string,
        )
        cmp_field(
          b,
          "\{base}.timescale",
          field(oi, "timescale"),
          field(ci, "timescale"),
          norm_decimal,
        )
        cmp_field(
          b,
          "\{base}.duration",
          field(oi, "duration"),
          field(ci, "duration"),
          norm_decimal,
        )
      }
      // candidate にだけある余分な track は fail
      for i in n..<c.length() {
        b.entry(
          "tracks[\{i}]",
          "fail",
          actual=Json::number(i.to_double()),
          note="candidate has extra track",
        )
      }
      for i in n..<o.length() {
        b.entry("tracks[\{i}]", "unverified", note="candidate track missing")
      }
    }
    (Some(o), None) => {
      let _ = o
      b.unverified("tracks", "candidate tracks missing or not an array")
    }
    (None, _) => b.unverified("tracks", "oracle tracks missing items")
  }
  b.excluded("tracks[].index", "candidate-only field (row position)")
  b.excluded("tracks[].codec", "candidate-only field (web extension)")
}

///|
/// oracle samples.items と candidate samples の要素比較。
fn compare_samples(b : DiffBuilder, oracle : Json?, candidate : Json?) -> Unit {
  let o_items = match oracle {
    Some(o) =>
      match field(o, "status") {
        Some(String("ok")) =>
          match field(o, "items") {
            Some(Array(items)) => Some(items)
            _ => None
          }
        Some(String(s)) => {
          b.unverified("samples", "oracle status: \{s}")
          return
        }
        _ => {
          b.unverified("samples", "oracle samples missing status")
          return
        }
      }
    None => {
      b.unverified("samples", "oracle report missing samples")
      return
    }
  }
  let c_items = match candidate {
    Some(Array(items)) => Some(items)
    _ => None
  }
  match (o_items, c_items) {
    (Some(o), Some(c)) => {
      let n = if o.length() < c.length() { o.length() } else { c.length() }
      for i in 0..<n {
        let oi = o[i]
        let ci = c[i]
        let base = "samples[\{i}]"
        // oracle index は 1 始まり、candidate は 0 始まり
        cmp_field(
          b,
          "\{base}.track_id",
          field(oi, "track_id"),
          field(ci, "track_id"),
          norm_decimal,
        )
        cmp_field(
          b,
          "\{base}.sample_entry",
          field(oi, "sample_entry"),
          field(ci, "sample_entry"),
          norm_fourcc,
        )
        cmp_field(
          b,
          "\{base}.keyframe",
          field(oi, "keyframe"),
          field(ci, "keyframe"),
          norm_bool,
        )
        cmp_field(
          b,
          "\{base}.timestamp",
          field(oi, "dts"),
          field(ci, "timestamp"),
          norm_decimal,
        )
        cmp_field(
          b,
          "\{base}.duration",
          field(oi, "duration"),
          field(ci, "duration"),
          norm_decimal,
        )
        cmp_field(
          b,
          "\{base}.composition_time_offset",
          field(oi, "pts_offset"),
          field(ci, "composition_time_offset"),
          norm_decimal_nullable,
        )
        cmp_field(
          b,
          "\{base}.data_offset",
          field(oi, "data_offset"),
          field(ci, "data_offset"),
          norm_decimal,
        )
        cmp_field(
          b,
          "\{base}.data_size",
          field(oi, "data_size"),
          field(ci, "data_size"),
          norm_decimal,
        )
      }
      for i in n..<o.length() {
        b.entry(
          "samples[\{i}]",
          "unverified",
          note="beyond candidate sample window",
        )
      }
      for i in n..<c.length() {
        b.entry(
          "samples[\{i}]",
          "fail",
          actual=Json::number(i.to_double()),
          note="candidate has extra sample",
        )
      }
    }
    (Some(_), None) =>
      b.unverified("samples", "candidate samples missing or not an array")
    (None, _) => b.unverified("samples", "oracle samples missing items")
  }
}

///|
/// candidate のネストした box tree を pre-order で平坦化する。
/// (depth, type, start, header_bytes, declared_size, total_size)
priv struct FlatNode {
  depth : String
  type_name : String
  start : String
  header_bytes : String
  declared_size : String
  total_size : String
}

///|
fn flatten_candidate_tree(
  nodes : Array[Json],
  depth : Int32,
  out : Array[FlatNode],
) -> Unit {
  for node in nodes {
    let t = match field(node, "type") {
      Some(String(s)) => s
      _ => "<non-string>"
    }
    let start = match field(node, "offset") {
      Some(v) => decimal_repr(v).unwrap_or("<bad>")
      None => "<missing>"
    }
    let hb = match field(node, "header_size") {
      Some(v) => decimal_repr(v).unwrap_or("<bad>")
      None => "<missing>"
    }
    let ds = match field(node, "declared_size") {
      Some(v) => decimal_repr(v).unwrap_or("<bad>")
      None => "<missing>"
    }
    let ts = match field(node, "size") {
      Some(v) => decimal_repr(v).unwrap_or("<bad>")
      None => "<missing>"
    }
    out.push({
      depth: depth.to_string(),
      type_name: t,
      start,
      header_bytes: hb,
      declared_size: ds,
      total_size: ts,
    })
    match field(node, "children") {
      Some(Array(children)) => flatten_candidate_tree(children, depth + 1, out)
      _ => ()
    }
  }
}

///|
/// oracle の flat node 配列を FlatNode へ正規化する。
fn oracle_flat_node(v : Json) -> FlatNode? {
  guard v is Object(_) else { return None }
  let d = decimal_repr(field(v, "depth").unwrap_or(Json::null())).unwrap_or(
    "<bad>",
  )
  let t = as_string(field(v, "type").unwrap_or(Json::null())).unwrap_or(
    "<non-string>",
  )
  let start = decimal_repr(field(v, "start").unwrap_or(Json::null())).unwrap_or(
    "<bad>",
  )
  let hb = decimal_repr(field(v, "header_bytes").unwrap_or(Json::null())).unwrap_or(
    "<bad>",
  )
  let ds = decimal_repr(field(v, "declared_size").unwrap_or(Json::null())).unwrap_or(
    "<bad>",
  )
  let ts = decimal_repr(field(v, "total_size").unwrap_or(Json::null())).unwrap_or(
    "<bad>",
  )
  Some({
    depth: d.to_string(),
    type_name: t,
    start,
    header_bytes: hb,
    declared_size: ds,
    total_size: ts,
  })
}

///|
/// FlatNode のキー (順序非依存比較用)。start は一意なので主キーに使う。
fn flat_key(n : FlatNode) -> String {
  "\{n.start}|\{n.depth}|\{n.type_name}"
}

///|
/// box tree の比較。順序非依存 (start でマッチ) + `box_tree.order` 分離。
fn compare_box_tree(b : DiffBuilder, oracle : Json?, candidate : Json?) -> Unit {
  // oracle 側: box_tree.tree.nodes
  let o_nodes = match oracle {
    Some(o) =>
      match field(o, "tree") {
        Some(t) =>
          match field(t, "status") {
            Some(String("ok")) =>
              match field(t, "nodes") {
                Some(Array(items)) => Some(items)
                _ => None
              }
            Some(String(s)) => {
              b.unverified("box_tree", "oracle tree status: \{s}")
              return
            }
            _ => {
              b.unverified("box_tree", "oracle box_tree missing status")
              return
            }
          }
        None => {
          b.unverified("box_tree", "oracle report missing box_tree.tree")
          return
        }
      }
    None => {
      b.unverified("box_tree", "oracle report missing box_tree")
      return
    }
  }
  // candidate 側: box_tree (ネスト配列)
  let c_roots = match candidate {
    Some(Array(items)) => Some(items)
    _ => None
  }
  match (o_nodes, c_roots) {
    (Some(o_items), Some(c_items)) => {
      // oracle flat
      let o_flat : Array[FlatNode] = []
      for item in o_items {
        match oracle_flat_node(item) {
          Some(n) => o_flat.push(n)
          None => b.unverified("box_tree.nodes[]", "oracle node not an object")
        }
      }
      // candidate flat
      let c_flat : Array[FlatNode] = []
      flatten_candidate_tree(c_items, 1, c_flat)
      // start キーでマッチング (start は各ノード一意)
      let o_by_key : Map[String, FlatNode] = Map([])
      for n in o_flat {
        o_by_key[flat_key(n)] = n
      }
      let c_by_key : Map[String, FlatNode] = Map([])
      for n in c_flat {
        c_by_key[flat_key(n)] = n
      }
      // 両方にあるキーを比較
      let mut matched = 0
      for kv in o_by_key {
        let (k, on) = kv
        match c_by_key.get(k) {
          Some(cn) => {
            matched += 1
            let base = "box_tree[\{on.type_name}@\{on.start}]"
            cmp_field(
              b,
              "\{base}.type",
              Some(Json(on.type_name)),
              Some(Json(cn.type_name)),
              norm_string,
            )
            cmp_field(
              b,
              "\{base}.start",
              Some(Json(on.start)),
              Some(Json(cn.start)),
              norm_decimal,
            )
            cmp_field(
              b,
              "\{base}.header_bytes",
              Some(Json(on.header_bytes)),
              Some(Json(cn.header_bytes)),
              norm_decimal,
            )
            cmp_field(
              b,
              "\{base}.declared_size",
              Some(Json(on.declared_size)),
              Some(Json(cn.declared_size)),
              norm_decimal,
            )
            cmp_field(
              b,
              "\{base}.total_size",
              Some(Json(on.total_size)),
              Some(Json(cn.total_size)),
              norm_decimal,
            )
          }
          None =>
            // oracle のみにあるノード = candidate が expand しないコンテナ内
            b.excluded(
              "box_tree:\{on.type_name}@\{on.start}",
              "candidate does not expand this subtree",
            )
        }
      }
      for kv in c_by_key {
        let (k, cn) = kv
        if o_by_key.get(k) is None {
          b.fail(
            "box_tree:\{cn.type_name}@\{cn.start}",
            Json::null(),
            Json(cn.type_name),
            note="candidate-only node",
          )
        }
      }
      if matched > 0 {
        b.pass("box_tree.matched_nodes", Json::number(matched.to_double()))
      }
      // 順序差: DFS 列 (depth,type,start) の比較。candidate が expand しない
      // subtree による差は coverage 差であって順序差ではないので、oracle 側は
      // candidate が実際に観測した start に絞ってから比較する。
      let c_starts : Map[String, Bool] = Map([])
      for n in c_flat {
        c_starts[n.start] = true
      }
      let o_seq = o_flat
        .filter(fn(n) { c_starts.contains(n.start) })
        .map(fn(n) { "\{n.depth}:\{n.type_name}:\{n.start}" })
      let c_seq = c_flat.map(fn(n) { "\{n.depth}:\{n.type_name}:\{n.start}" })
      if o_seq == c_seq {
        b.pass("box_tree.order", Json("preorder identical"))
      } else {
        b.entry(
          "box_tree.order",
          "fail",
          expected=Json(o_seq.join(",")),
          actual=Json(c_seq.join(",")),
          note="traversal order differs (upstream notes order may not match input order)",
        )
      }
    }
    (Some(_), None) =>
      b.unverified("box_tree", "candidate box_tree missing or not an array")
    (None, _) => b.unverified("box_tree", "oracle box_tree missing nodes")
  }
}

///|
/// kind / format の比較。
fn compare_kind(b : DiffBuilder, oracle : Json?, candidate : Json?) -> Unit {
  match oracle {
    Some(o) =>
      match field(o, "status") {
        Some(String("ok")) =>
          cmp_field(b, "kind", field(o, "value"), candidate, norm_kind)
        Some(String(s)) => b.unverified("kind", "oracle kind status: \{s}")
        _ => b.unverified("kind", "oracle kind missing status")
      }
    None => b.unverified("kind", "oracle report missing kind")
  }
}

///|
/// 状態/エラーの比較。candidate.state=="failed" または oracle 側 status=="error"
/// のとき、両側のエラー分類を正規化して突き合わせる。
fn compare_outcome(b : DiffBuilder, oracle : Json?, candidate : Json?) -> Unit {
  // oracle 側エラーは各セクションの status=="error" を集約
  let mut oracle_err : Json? = None
  match oracle {
    Some(o) => {
      for section in ["kind", "tracks", "samples"] {
        match field(o, section) {
          Some(sec) =>
            match field(sec, "status") {
              Some(String("error")) =>
                match field(sec, "error") {
                  Some(e) => oracle_err = Some(e)
                  None => ()
                }
              _ => ()
            }
          None => ()
        }
      }
      // box_tree.tree.status == "error"
      match field(o, "box_tree") {
        Some(bt) =>
          match field(bt, "tree") {
            Some(t) =>
              match field(t, "status") {
                Some(String("error")) =>
                  match field(t, "error_kind") {
                    Some(ek) =>
                      oracle_err = Some(
                        Json::object(
                          {
                            let m : Map[String, Json] = Map([])
                            m["classification"] = Json("decode_error")
                            m["error_kind"] = ek
                            m
                          },
                        ),
                      )
                    None => ()
                  }
                _ => ()
              }
            None => ()
          }
        None => ()
      }
    }
    None => ()
  }
  let cand_err = match candidate {
    Some(c) =>
      match field(c, "state") {
        Some(String("failed")) => field(c, "error")
        _ => None
      }
    None => None
  }
  match (oracle_err, cand_err) {
    (None, None) => b.pass("outcome", Json("both_succeeded"))
    (Some(e), Some(a)) => {
      // 分類を突き合わせる
      let o_kind = match field(e, "error_kind") {
        Some(ek) => ek
        None =>
          match field(e, "classification") {
            Some(cl) => cl
            None => Json::null()
          }
      }
      let c_kind = match field(a, "kind") {
        Some(k) => k
        None => Json::null()
      }
      cmp_field(b, "error.kind", Some(o_kind), Some(c_kind), norm_error_kind)
    }
    (Some(e), None) =>
      b.fail(
        "outcome",
        Json("error"),
        Json("success"),
        note="oracle failed but candidate succeeded: \{e.stringify()}",
      )
    (None, Some(a)) =>
      b.fail(
        "outcome",
        Json("success"),
        Json("error"),
        note="candidate failed but oracle succeeded: \{a.stringify()}",
      )
  }
}

///|
/// メタ情報。upstream_sha / fixture_sha256 の存在を確認する。
fn compare_meta(b : DiffBuilder, meta : Json?) -> Unit {
  match meta {
    Some(m) =>
      for key in ["upstream_sha", "fixture_sha256", "fixture_name"] {
        match field(m, key) {
          Some(v) => b.pass("meta.\{key}", v)
          None => b.unverified("meta.\{key}", "missing in meta")
        }
      }
    None => b.unverified("meta", "meta missing entirely")
  }
}

///|
/// oracle / candidate / meta の 3 JSON を突き合わせ、差分レポート Json を返す。
///
/// verdict: "pass" / "fail" / "unverified"。`not_run` は除外項目の記録にのみ使う。
pub fn diff_reports(oracle : Json, candidate : Json, meta : Json) -> Json {
  let b = DiffBuilder::new()
  compare_meta(b, Some(meta))
  compare_kind(b, field(oracle, "kind"), field(candidate, "format"))
  compare_tracks(b, field(oracle, "tracks"), field(candidate, "tracks"))
  compare_samples(b, field(oracle, "samples"), field(candidate, "samples"))
  compare_box_tree(b, field(oracle, "box_tree"), field(candidate, "box_tree"))
  compare_outcome(b, Some(oracle), Some(candidate))
  // 集計
  let mut npass = 0
  let mut nfail = 0
  let mut nunv = 0
  for e in b.entries {
    match e.verdict {
      "pass" => npass += 1
      "fail" => nfail += 1
      _ => nunv += 1
    }
  }
  let verdict = if nfail > 0 {
    "fail"
  } else if nunv > 0 {
    "unverified"
  } else {
    "pass"
  }
  let entries : Array[Json] = []
  for e in b.entries {
    let obj : Map[String, Json] = Map([])
    obj["path"] = Json(e.path)
    obj["verdict"] = Json(e.verdict)
    if e.expected != Json::null() || e.actual != Json::null() {
      obj["expected"] = e.expected
      obj["actual"] = e.actual
    }
    if !e.note.is_empty() {
      obj["note"] = Json(e.note)
    }
    entries.push(Json::object(obj))
  }
  Json::object(
    {
      let m : Map[String, Json] = Map([])
      m["schema"] = Json("mp4-diff-report/1")
      m["meta"] = meta
      m["verdict"] = Json(verdict)
      m["stats"] = Json::object(
        {
          let s : Map[String, Json] = Map([])
          s["pass"] = Json::number(npass.to_double())
          s["fail"] = Json::number(nfail.to_double())
          s["unverified"] = Json::number(nunv.to_double())
          s["not_run"] = Json::number(b.excluded.length().to_double())
          s
        },
      )
      m["entries"] = Json(entries)
      m["excluded"] = Json(b.excluded)
      m
    },
  )
}

///|
/// 実行不能 (oracle wasm 不在 / candidate ビルド失敗) のときの UNVERIFIED
/// レポート。PASS と混同しないための専用エントリ。
pub fn unverified_report(meta : Json, reason : String) -> Json {
  let b = DiffBuilder::new()
  b.entry("run", "unverified", note=reason)
  compare_meta(b, Some(meta))
  Json::object(
    {
      let m : Map[String, Json] = Map([])
      m["schema"] = Json("mp4-diff-report/1")
      m["meta"] = meta
      m["verdict"] = Json("unverified")
      m["stats"] = Json::object(
        {
          let s : Map[String, Json] = Map([])
          s["pass"] = Json::number(0.0)
          s["fail"] = Json::number(0.0)
          s["unverified"] = Json::number(1.0)
          s["not_run"] = Json::number(0.0)
          s
        },
      )
      m["entries"] = Json(
        b.entries.map(fn(e) {
          Json::object(
            {
              let o : Map[String, Json] = Map([])
              o["path"] = Json(e.path)
              o["verdict"] = Json(e.verdict)
              o["note"] = Json(e.note)
              o
            },
          )
        }),
      )
      m["excluded"] = Json(b.excluded)
      m
    },
  )
}

///|
/// JSON 文字列入力版。parse 失敗は `Err` として返す。
pub fn diff_reports_json(
  oracle_json : String,
  candidate_json : String,
  meta_json : String,
) -> String raise {
  let oracle = @json.parse(oracle_json[:])
  let candidate = @json.parse(candidate_json[:])
  let meta = @json.parse(meta_json[:])
  diff_reports(oracle, candidate, meta).stringify()
}
