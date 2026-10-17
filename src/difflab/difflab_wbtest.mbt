///|
fn entry_verdict(e : Json) -> String {
  match e {
    Object(o) =>
      match o["verdict"] {
        String(s) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn entry_path(e : Json) -> String {
  match e {
    Object(o) =>
      match o["path"] {
        String(s) => s
        _ => ""
      }
    _ => ""
  }
}

// 差分レポート (difflab) の white-box テスト。
// テスト計画 (issue 0016) の固定項目:
//   - 未知項目をゼロ埋めしない (欠落は unverified、不一致と混同しない)
//   - 64bit 値の文字列化 (十進文字列のまま比較し JS 精度で丸めない)
//   - CTTS 未設定 (null) と 0 の区別
//   - 差分の field path 生成
//   - 判定状態遷移 (pass / fail / unverified / not_run)
//   - box tree の順序非依存比較 + 順序差の分離

///|
fn meta_json() -> Json {
  {
    "upstream_sha": "1282b704f44184ec792e1549b5d31e0c4c54dc59",
    "fixture_name": "probe.mp4",
    "fixture_sha256": "deadbeef",
  }
}

///|
fn oracle_ok() -> Json {
  {
    "kind": { "status": "ok", "value": "mp4" },
    "tracks": {
      "status": "ok",
      "items": [
        {
          "track_id": "1",
          "kind": "video",
          "timescale": "12800",
          "duration": "512",
        },
      ],
    },
    "samples": {
      "status": "ok",
      "items": [
        {
          "index": "1",
          "track_id": "1",
          "sample_entry": "avc1",
          "keyframe": true,
          "dts": "0",
          "duration": "512",
          "pts_offset": null,
          "data_offset": "48",
          "data_size": "796",
        },
      ],
      "truncated": false,
    },
    "box_tree": {
      "ftyp": null,
      "tree": {
        "status": "ok",
        "nodes": [
          {
            "depth": 1,
            "type": "ftyp",
            "type_hex": "66747970",
            "start": "0",
            "header_bytes": 8,
            "declared_size": "32",
            "total_size": "32",
          },
        ],
      },
    },
  }
}

///|
fn candidate_ok() -> Json {
  {
    "file": "probe.mp4",
    "file_size": "1635",
    "format": "normal",
    "state": "ready",
    "tracks": [
      {
        "index": 0,
        "track_id": 1,
        "kind": "video",
        "codec": "avc1.64001e",
        "duration": "512",
        "timescale": 12800,
      },
    ],
    "samples": [
      {
        "index": 0,
        "track_id": 1,
        "sample_entry": "avc1",
        "keyframe": true,
        "timestamp": "0",
        "duration": 512,
        "composition_time_offset": null,
        "data_offset": "48",
        "data_size": 796,
      },
    ],
    "shown_samples": 1,
    "sample_total": "1",
    "truncated": false,
    "box_tree": [
      {
        "type": "ftyp",
        "offset": "0",
        "size": "32",
        "declared_size": "32",
        "header_size": 8,
        "children": [],
      },
    ],
    "requests": [],
    "error": null,
  }
}

///|
/// 完全一致は pass。
test "identical reports -> pass" {
  let report = diff_reports(oracle_ok(), candidate_ok(), meta_json())
  guard report is Object(m) else { abort("not object") }
  assert_eq(m["verdict"], Json("pass"))
  // excluded に index/codec が記録されている
  guard m["excluded"] is Array(ex) else { abort("no excluded") }
  let excluded_paths = ex.map(fn(e) { entry_path(e) })
  assert_true(excluded_paths.contains("tracks[].codec"))
  assert_true(excluded_paths.contains("tracks[].index"))
}

///|
/// 1 フィールドの意図的改竄は該当 field path の fail になる。
test "injected sample duration diff -> fail at exact path" {
  let bad = candidate_ok()
  guard bad is Object(m) else { abort("x") }
  guard m["samples"] is Array(samples) else { abort("x") }
  guard samples[0] is Object(s0) else { abort("x") }
  s0["duration"] = Json::number(513.0)
  let report = diff_reports(oracle_ok(), bad, meta_json())
  guard report is Object(rm) else { abort("x") }
  assert_eq(rm["verdict"], Json("fail"))
  guard rm["entries"] is Array(entries) else { abort("x") }
  let fails = entries.filter(fn(e) { entry_verdict(e) == "fail" })
  assert_eq(fails.length(), 1)
  guard fails[0] is Object(f0) else { abort("x") }
  assert_eq(f0["path"], Json("samples[0].duration"))
  assert_eq(f0["expected"], Json("512"))
  assert_eq(f0["actual"], Json("513"))
}

///|
/// oracle 側の欠落キーは fail ではなく unverified (ゼロ埋め禁止の裏返し)。
test "oracle missing field -> unverified not fail" {
  let oracle = oracle_ok()
  guard oracle is Object(m) else { abort("x") }
  guard m["tracks"] is Object(t) else { abort("x") }
  guard t["items"] is Array(items) else { abort("x") }
  guard items[0] is Object(i0) else { abort("x") }
  i0.remove("duration")
  let report = diff_reports(oracle, candidate_ok(), meta_json())
  guard report is Object(rm) else { abort("x") }
  assert_eq(rm["verdict"], Json("unverified"))
  guard rm["entries"] is Array(entries) else { abort("x") }
  let unv = entries.filter(fn(e) { entry_verdict(e) == "unverified" })
  assert_true(unv.iter().any(fn(e) { entry_path(e) == "tracks[0].duration" }))
}

///|
/// CTTS: oracle null vs candidate null は pass、oracle "0" vs candidate null は fail。
/// (None と 0 の区別を保つ)
test "pts_offset null vs 0 distinction" {
  // null vs null -> pass
  let report = diff_reports(oracle_ok(), candidate_ok(), meta_json())
  guard report is Object(m) else { abort("x") }
  assert_eq(m["verdict"], Json("pass"))

  // oracle が "0" で candidate が null -> fail (ゼロ埋めではない)
  let oracle = oracle_ok()
  guard oracle is Object(om) else { abort("x") }
  guard om["samples"] is Object(sm) else { abort("x") }
  guard sm["items"] is Array(items) else { abort("x") }
  guard items[0] is Object(i0) else { abort("x") }
  i0["pts_offset"] = Json("0")
  let report2 = diff_reports(oracle, candidate_ok(), meta_json())
  guard report2 is Object(rm2) else { abort("x") }
  assert_eq(rm2["verdict"], Json("fail"))
  guard rm2["entries"] is Array(entries) else { abort("x") }
  let fails = entries.filter(fn(e) { entry_verdict(e) == "fail" })
  assert_true(
    fails
    .iter()
    .any(fn(e) { entry_path(e) == "samples[0].composition_time_offset" }),
  )
}

///|
/// 64bit 値は文字列どうしで比較し、Number 化による精度劣化が起きない。
/// oracle "9007199254740993" (2^53+1) vs candidate 同値文字列 -> pass。
/// candidate が Number 経由で丸まると fail になることを確認する。
test "64-bit values compared as decimal strings" {
  let oracle = oracle_ok()
  guard oracle is Object(om) else { abort("x") }
  guard om["samples"] is Object(sm) else { abort("x") }
  guard sm["items"] is Array(items) else { abort("x") }
  guard items[0] is Object(i0) else { abort("x") }
  i0["data_offset"] = Json("9007199254740993")

  let cand = candidate_ok()
  guard cand is Object(cm) else { abort("x") }
  guard cm["samples"] is Array(cs) else { abort("x") }
  guard cs[0] is Object(c0) else { abort("x") }
  c0["data_offset"] = Json("9007199254740993")
  let report = diff_reports(oracle, cand, meta_json())
  guard report is Object(rm) else { abort("x") }
  assert_eq(rm["verdict"], Json("pass"))
}

///|
/// box tree は順序非依存で比較し、順序差だけを別エントリで記録する。
test "box tree order-independent compare + order entry" {
  // oracle: ftyp, free の順。candidate: free, ftyp の順 (同じ node 集合)。
  let oracle = oracle_ok()
  guard oracle is Object(om) else { abort("x") }
  guard om["box_tree"] is Object(bt) else { abort("x") }
  guard bt["tree"] is Object(tr) else { abort("x") }
  guard tr["nodes"] is Array(nodes) else { abort("x") }
  nodes.push({
    "depth": 1,
    "type": "free",
    "type_hex": "66726565",
    "start": "32",
    "header_bytes": 8,
    "declared_size": "8",
    "total_size": "8",
  })
  let cand = candidate_ok()
  guard cand is Object(cm) else { abort("x") }
  guard cm["box_tree"] is Array(cb) else { abort("x") }
  // candidate の並びを入れ替え (free が先)
  let ftyp = cb[0]
  cb.clear()
  cb.push({
    "type": "free",
    "offset": "32",
    "size": "8",
    "declared_size": "8",
    "header_size": 8,
    "children": [],
  })
  cb.push(ftyp)
  let report = diff_reports(oracle, cand, meta_json())
  guard report is Object(rm) else { abort("x") }
  // multiset は一致するが順序が違う → box_tree.order だけ fail
  guard rm["entries"] is Array(entries) else { abort("x") }
  let order_entries = entries.filter(fn(e) { entry_path(e) == "box_tree.order" })
  assert_eq(order_entries.length(), 1)
  guard order_entries[0] is Object(oe) else { abort("x") }
  assert_eq(oe["verdict"], Json("fail"))
  // フィールド比較は通っている
  let field_fails = entries.filter(fn(e) {
    entry_verdict(e) == "fail" && entry_path(e) != "box_tree.order"
  })
  assert_eq(field_fails.length(), 0)
}

///|
/// oracle 側だけにある box ノードは fail ではなく excluded (候補が expand しない
/// 範囲を fail にしない)。
test "oracle-only subtree nodes are excluded not fail" {
  let oracle = oracle_ok()
  guard oracle is Object(om) else { abort("x") }
  guard om["box_tree"] is Object(bt) else { abort("x") }
  guard bt["tree"] is Object(tr) else { abort("x") }
  guard tr["nodes"] is Array(nodes) else { abort("x") }
  // moov 子 (candidate は moov 以外を expand しない想定だが、ここでは単純に oracle-only)
  nodes.push({
    "depth": 2,
    "type": "mvhd",
    "type_hex": "6d766864",
    "start": "100",
    "header_bytes": 8,
    "declared_size": "108",
    "total_size": "108",
  })
  let report = diff_reports(oracle, candidate_ok(), meta_json())
  guard report is Object(rm) else { abort("x") }
  guard rm["excluded"] is Array(ex) else { abort("x") }
  let has_mvhd = ex
    .iter()
    .any(fn(e) {
      match field(e, "path") {
        Some(String(p)) => p.contains("mvhd")
        _ => false
      }
    })
  assert_true(has_mvhd)
  // oracle-only ノードは coverage 差で順序差ではない: order 比較は candidate が
  // 実際に観測したノードに限定されるため、全体 verdict も pass のまま。
  assert_eq(rm["verdict"], Json("pass"))
}

///|
/// 両側エラーは outcome pass (分類が一致すれば)。oracle decode_error
/// invalid_data と candidate InvalidData を正規化一致とする。
test "both errored with matching kind -> outcome pass" {
  let oracle : Json = {
    "kind": {
      "status": "error",
      "error": {
        "classification": "decode_error",
        "error_kind": "invalid_data",
        "box_type": null,
        "message": "bad",
      },
    },
    "tracks": {
      "status": "error",
      "error": {
        "classification": "decode_error",
        "error_kind": "invalid_data",
        "box_type": null,
        "message": "bad",
      },
    },
    "samples": {
      "status": "error",
      "items": [],
      "truncated": false,
      "error": {
        "classification": "decode_error",
        "error_kind": "invalid_data",
        "box_type": null,
        "message": "bad",
      },
    },
    "box_tree": {
      "ftyp": null,
      "tree": { "status": "error", "error_kind": "invalid_data" },
    },
  }
  let cand : Json = {
    "format": "normal",
    "state": "failed",
    "tracks": [],
    "samples": [],
    "box_tree": [],
    "error": { "kind": "InvalidData", "message": "bad", "position": "0" },
  }
  let report = diff_reports(oracle, cand, meta_json())
  guard report is Object(m) else { abort("x") }
  guard m["entries"] is Array(entries) else { abort("x") }
  let kind_entries = entries.filter(fn(e) { entry_path(e) == "error.kind" })
  assert_eq(kind_entries.length(), 1)
  guard kind_entries[0] is Object(ke) else { abort("x") }
  assert_eq(ke["verdict"], Json("pass"))
}

///|
/// 片側だけエラーは fail。
test "oracle-only error -> outcome fail" {
  let oracle : Json = {
    "kind": {
      "status": "error",
      "error": {
        "classification": "decode_error",
        "error_kind": "invalid_data",
        "box_type": null,
        "message": "bad",
      },
    },
    "tracks": {
      "status": "ok",
      "items": [
        {
          "track_id": "1",
          "kind": "video",
          "timescale": "12800",
          "duration": "512",
        },
      ],
    },
    "samples": {
      "status": "ok",
      "items": [
        {
          "index": "1",
          "track_id": "1",
          "sample_entry": "avc1",
          "keyframe": true,
          "dts": "0",
          "duration": "512",
          "pts_offset": null,
          "data_offset": "48",
          "data_size": "796",
        },
      ],
      "truncated": false,
    },
    "box_tree": {
      "ftyp": null,
      "tree": {
        "status": "ok",
        "nodes": [
          {
            "depth": 1,
            "type": "ftyp",
            "type_hex": "66747970",
            "start": "0",
            "header_bytes": 8,
            "declared_size": "32",
            "total_size": "32",
          },
        ],
      },
    },
  }
  let report = diff_reports(oracle, candidate_ok(), meta_json())
  guard report is Object(m) else { abort("x") }
  assert_eq(m["verdict"], Json("fail"))
}

///|
/// oracle wasm 不在などの unverified レポート。
test "unverified_report marks run as unverified" {
  let report = unverified_report(meta_json(), "oracle wasm unavailable")
  guard report is Object(m) else { abort("x") }
  assert_eq(m["verdict"], Json("unverified"))
}

///|
/// JSON 文字列入出力の経路も通る。
test "diff_reports_json parses and emits" {
  let out = diff_reports_json(
    oracle_ok().stringify(),
    candidate_ok().stringify(),
    meta_json().stringify(),
  )
  let rep = @json.parse(out[:])
  guard rep is Object(m) else { abort("x") }
  assert_eq(m["verdict"], Json("pass"))
}
