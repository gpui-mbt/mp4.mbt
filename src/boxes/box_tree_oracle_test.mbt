///|
/// Rust oracle の box tree 走査 1 ノード分（生成データ用）。
struct OracleBoxTreeNode {
  depth : Int32
  box_type : Bytes
  start : UInt64
  header_bytes : Int32
  declared_size : UInt64
  total_size : UInt64
}

///|
/// Rust oracle の box tree 境界ケース 1 件分（生成データ用）。
struct OracleBoxTreeCase {
  name : String
  input : Bytes
  ok : Bool
  nodes : Array[OracleBoxTreeNode]
  error_kind : String
}

///|
/// Rust oracle が upstream `FtypBox` で読んだ `ftyp` の内容（生成データ用）。
struct OracleBoxTreeFtyp {
  major_brand : Bytes
  minor_version : UInt32
  compatible_brands : Array[Bytes]
}

///|
/// Rust oracle の fixture 走査 1 件分（生成データ用）。
struct OracleBoxTreeFixture {
  name : String
  input : Bytes
  nodes : Array[OracleBoxTreeNode]
  ftyp : OracleBoxTreeFtyp?
}

///|
/// エラー分類を oracle の JSON と同じ snake_case 名にする。
fn oracle_kind_name(kind : @bytes.ErrorKind) -> String {
  match kind {
    InvalidInput => "invalid_input"
    InvalidData => "invalid_data"
    InsufficientBuffer => "insufficient_buffer"
    Unsupported => "unsupported"
  }
}

///|
/// oracle の観測ノード列と MoonBit 側の木を比較する。
fn assert_box_tree_matches_oracle(
  label : String,
  expected : Array[OracleBoxTreeNode],
  nodes : Array[@boxes.BoxNode],
) -> Unit raise {
  let actual = @boxes.flatten_box_tree(nodes)
  if actual.length() != expected.length() {
    fail(
      "\{label}: node count differs (oracle=\{expected.length()}, moonbit=\{actual.length()})",
    )
  }
  for i in 0..<actual.length() {
    let (depth, node) = actual[i]
    let want = expected[i]
    if depth != want.depth ||
      node.box_type().as_bytes() != want.box_type ||
      node.start() != want.start ||
      node.header_bytes() != want.header_bytes ||
      node.declared_size() != want.declared_size ||
      node.total_size() != want.total_size {
      fail(
        "\{label}: node \{i} differs (oracle=\{want.depth}/\{want.box_type}/\{want.start}/\{want.header_bytes}/\{want.declared_size}/\{want.total_size}, moonbit=\{depth}/\{node.box_type().as_bytes()}/\{node.start()}/\{node.header_bytes()}/\{node.declared_size()}/\{node.total_size()})",
      )
    }
  }
}

///|
/// oracle の `ftyp` と MoonBit 側の [`@boxes.FtypBox`] を比較する。
fn assert_ftyp_matches_oracle(
  label : String,
  expected : OracleBoxTreeFtyp,
  input : Bytes,
) -> Unit raise {
  let cursor = @bytes.ReadCursor::new(input)
  let ftyp : @boxes.FtypBox = @bytes.decode_from(cursor)
  if ftyp.major_brand.as_bytes() != expected.major_brand {
    fail("\{label}: major_brand differs")
  }
  if ftyp.minor_version != expected.minor_version {
    fail(
      "\{label}: minor_version differs (oracle=\{expected.minor_version}, moonbit=\{ftyp.minor_version})",
    )
  }
  if ftyp.compatible_brands.length() != expected.compatible_brands.length() {
    fail(
      "\{label}: compatible brand count differs (oracle=\{expected.compatible_brands.length()}, moonbit=\{ftyp.compatible_brands.length()})",
    )
  }
  for i in 0..<expected.compatible_brands.length() {
    if ftyp.compatible_brands[i].as_bytes() != expected.compatible_brands[i] {
      fail("\{label}: compatible brand \{i} differs")
    }
  }
}

///|
test "box tree matches the rust oracle case table" {
  inspect(oracle_box_tree_cases.length() > 0, content="true")
  for case in oracle_box_tree_cases {
    let cursor = @bytes.ReadCursor::new(case.input)
    let nodes : Array[@boxes.BoxNode]? = try
      @boxes.build_box_tree(cursor)
    catch {
      @bytes.Mp4Error(kind~, reason~, ..) => {
        if case.ok {
          fail(
            "\{case.name}: oracle succeeded, but moonbit failed with \{oracle_kind_name(kind)}: \{reason}",
          )
        }
        if oracle_kind_name(kind) != case.error_kind {
          fail(
            "\{case.name}: oracle kind \{case.error_kind}, moonbit kind \{oracle_kind_name(kind)} (\{reason})",
          )
        }
        None
      }
    } noraise {
      nodes => Some(nodes)
    }
    match nodes {
      Some(nodes) =>
        if case.ok {
          assert_box_tree_matches_oracle(case.name, case.nodes, nodes)
        } else {
          fail(
            "\{case.name}: oracle failed with \{case.error_kind}, but moonbit succeeded",
          )
        }
      None => ()
    }
  }
}

///|
test "box tree matches the rust oracle for embedded fixtures" {
  inspect(oracle_box_tree_fixtures.length() > 0, content="true")
  for fixture in oracle_box_tree_fixtures {
    let cursor = @bytes.ReadCursor::new(fixture.input)
    let nodes = @boxes.build_box_tree(cursor)
    inspect(cursor.is_empty(), content="true")
    assert_box_tree_matches_oracle(fixture.name, fixture.nodes, nodes)
    match fixture.ftyp {
      Some(expected) =>
        assert_ftyp_matches_oracle(fixture.name, expected, fixture.input)
      None => fail("\{fixture.name}: oracle found no ftyp")
    }
  }
}
