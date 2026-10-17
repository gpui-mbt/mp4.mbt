///|
/// ボックス木の 1 ノード。
///
/// ペイロードは保持せず、位置・長さ・種別と子ノードだけを持つ観測情報である。
/// 表示（dump）や Rust oracle との差分比較（[`flatten_box_tree`]）は、この型の
/// 値だけで行える。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(
///     b"\x00\x00\x00\x10moov\x00\x00\x00\x08trak",
///   )
///   let nodes = @boxes.build_box_tree(cursor)
///   inspect(nodes.length(), content="1")
///   inspect(nodes[0].start(), content="0")
///   inspect(nodes[0].total_size(), content="16")
///   inspect(nodes[0].children().length(), content="1")
///   inspect(nodes[0].children()[0].box_type().to_string(), content="trak")
/// }
/// ```
pub struct BoxNode {
  /// ボックス種別
  box_type : @bytes.BoxType
  /// ボックス先頭のファイル内位置
  start : UInt64
  /// ヘッダーのバイト数
  header_bytes : Int32
  /// ヘッダーが宣言した合計サイズ（`size==0` のときは 0）
  declared_size : UInt64
  /// 実際の合計サイズ（`size==0` は読み取り範囲の末尾まで）
  total_size : UInt64
  /// 子ボックス（子を持たない種別では空）
  children : Array[BoxNode]
} derive(Debug)

///|
pub extend BoxNode with Debug::{to_repr}

///|
/// ボックス種別を返す。
pub fn BoxNode::box_type(self : BoxNode) -> @bytes.BoxType {
  self.box_type
}

///|
/// ボックス先頭のファイル内位置を返す。
pub fn BoxNode::start(self : BoxNode) -> UInt64 {
  self.start
}

///|
/// ヘッダーのバイト数を返す。
pub fn BoxNode::header_bytes(self : BoxNode) -> Int32 {
  self.header_bytes
}

///|
/// ヘッダーが宣言した合計サイズを返す（`size==0` のときは 0）。
pub fn BoxNode::declared_size(self : BoxNode) -> UInt64 {
  self.declared_size
}

///|
/// 実際の合計サイズを返す（`size==0` は読み取り範囲の末尾まで）。
pub fn BoxNode::total_size(self : BoxNode) -> UInt64 {
  self.total_size
}

///|
/// ボックス末尾の次のファイル内位置を返す。
pub fn BoxNode::end(self : BoxNode) -> UInt64 {
  self.start + self.total_size
}

///|
/// ペイロード先頭のファイル内位置を返す。
pub fn BoxNode::payload_start(self : BoxNode) -> UInt64 {
  self.start + self.header_bytes.to_uint64()
}

///|
/// ペイロード長を返す。
pub fn BoxNode::payload_size(self : BoxNode) -> UInt64 {
  self.total_size - self.header_bytes.to_uint64()
}

///|
/// `size==0`（末尾までの可変長）で書かれていたかどうかを返す。
pub fn BoxNode::is_variable_size(self : BoxNode) -> Bool {
  self.declared_size == 0UL
}

///|
/// 子ノードを返す。
pub fn BoxNode::children(self : BoxNode) -> Array[BoxNode] {
  self.children
}

///|
/// ノード 1 件を `dump` 用の 1 行へ整形する（`depth` はトップレベルを 1 とする）。
pub fn BoxNode::dump_line(self : BoxNode, depth : Int32) -> String {
  let size = if self.is_variable_size() {
    "\{self.total_size} (to end)"
  } else {
    self.total_size.to_string()
  }
  "d=\{depth} \{self.box_type.to_string()} start=\{self.start} size=\{size} header=\{self.header_bytes} payload=\{self.payload_size()}"
}

///|
/// ボックス木の走査設定。
pub struct BoxTreeOptions {
  /// 最大深さ（トップレベルを 1 とする）
  max_depth : Int32
  /// 総ノード数の上限
  max_nodes : Int32
  /// 子ボックスを持つ種別の判定
  is_container : (@bytes.BoxType) -> Bool
}

///|
/// ボックス木の総ノード数の既定上限。
pub const DEFAULT_MAX_BOX_TREE_NODES : Int32 = 65536

///|
/// 既定の走査設定を作る。
///
/// 深さは [`@bytes.DEFAULT_MAX_NESTING_DEPTH`]、ノード数は
/// [`DEFAULT_MAX_BOX_TREE_NODES`]、子を持つ種別は
/// [`is_plain_container_box_type`] を使う。
pub fn BoxTreeOptions::new() -> BoxTreeOptions {
  {
    max_depth: @bytes.DEFAULT_MAX_NESTING_DEPTH,
    max_nodes: DEFAULT_MAX_BOX_TREE_NODES,
    is_container: is_plain_container_box_type,
  }
}

///|
/// 最大深さだけを変えた設定を返す。
pub fn BoxTreeOptions::with_max_depth(
  self : BoxTreeOptions,
  max_depth : Int32,
) -> BoxTreeOptions {
  { max_depth, max_nodes: self.max_nodes, is_container: self.is_container, }
}

///|
/// 総ノード数の上限だけを変えた設定を返す。
pub fn BoxTreeOptions::with_max_nodes(
  self : BoxTreeOptions,
  max_nodes : Int32,
) -> BoxTreeOptions {
  { max_depth: self.max_depth, max_nodes, is_container: self.is_container, }
}

///|
/// 子ボックスを持つ種別の判定だけを差し替えた設定を返す。
pub fn BoxTreeOptions::with_container_predicate(
  self : BoxTreeOptions,
  is_container : (@bytes.BoxType) -> Bool,
) -> BoxTreeOptions {
  { max_depth: self.max_depth, max_nodes: self.max_nodes, is_container, }
}

///|
/// payload がそのまま子ボックスの列である種別かどうかを返す。
///
/// `moov` 以下と fragment の代表的なコンテナだけを対象にする。`stsd` や `meta` の
/// ように前置フィールドを持つボックスや、`avc1` などの sample entry（途中から子が
/// 始まる）は含めない。後続 Issue で型付きデコードと揃えて拡張する。
pub fn is_plain_container_box_type(box_type : @bytes.BoxType) -> Bool {
  let bytes = box_type.as_bytes()
  bytes == b"moov" ||
  bytes == b"trak" ||
  bytes == b"mdia" ||
  bytes == b"minf" ||
  bytes == b"stbl" ||
  bytes == b"edts" ||
  bytes == b"dinf" ||
  bytes == b"mvex" ||
  bytes == b"moof" ||
  bytes == b"traf" ||
  bytes == b"mfra" ||
  bytes == b"udta"
}

///|
/// 走査中の可変状態。
priv struct BoxTreeWalker {
  options : BoxTreeOptions
  mut node_count : Int32
}

///|
/// カーソルが指す領域のボックス木を構築する。
///
/// ペイロードは一切保持しない（子を持つ種別では再帰のため payload を view として
/// 共有するだけ）。`size==0` はトップレベルだけを許し、入れ子では
/// [`@bytes.ErrorKind::InvalidData`] で拒否する。深さの上限は `options` に従い、
/// 省略時はカーソルの [`@bytes.ParseLimits`] を使う。上限超過は
/// [`@bytes.ErrorKind::Unsupported`] になる。失敗した場合はカーソル位置を開始位置へ
/// 戻す。
pub fn build_box_tree(
  cursor : @bytes.ReadCursor,
  options? : BoxTreeOptions,
) -> Array[BoxNode] raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  let options = options.unwrap_or(
    BoxTreeOptions::new().with_max_depth(cursor.limits().max_nesting_depth()),
  )
  let walker : BoxTreeWalker = { options, node_count: 0, }
  walker.walk_level(cursor, 1)
}

///|
/// 1 レベル分のボックスを順に読み、ノード列を返す。
fn BoxTreeWalker::walk_level(
  self : BoxTreeWalker,
  cursor : @bytes.ReadCursor,
  depth : Int32,
) -> Array[BoxNode] raise @bytes.Mp4Error {
  let nodes : Array[BoxNode] = []
  while !cursor.is_empty() {
    nodes.push(self.walk_node(cursor, depth))
  }
  nodes
}

///|
/// 1 ボックスを読み、コンテナなら入れ子を再帰してノードを返す。
fn BoxTreeWalker::walk_node(
  self : BoxTreeWalker,
  cursor : @bytes.ReadCursor,
  depth : Int32,
) -> BoxNode raise @bytes.Mp4Error {
  let start = cursor.offset()
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  let header_bytes = header.external_size()
  let total_size = header_bytes.to_uint64() + payload.length().to_uint64()
  let declared_size = header.box_size().get()
  let box_type = header.box_type()
  if depth > 1 && declared_size == 0UL {
    raise @bytes.Mp4Error::invalid_data(
        "size=0 box is only allowed at the top level",
      )
      .with_offset(start)
      .with_box_type(box_type)
  }
  self.node_count += 1
  if self.node_count > self.options.max_nodes {
    raise @bytes.Mp4Error::unsupported(
        "box tree node count exceeds BoxTreeOptions.max_nodes=\{self.options.max_nodes}",
      )
      .with_offset(start)
      .with_box_type(box_type)
  }
  let children = if (self.options.is_container)(box_type) &&
    payload.length() > 0 {
    if depth >= self.options.max_depth {
      raise @bytes.Mp4Error::unsupported(
          "nesting depth \{depth + 1} exceeds BoxTreeOptions.max_depth=\{self.options.max_depth}",
        )
        .with_offset(start)
        .with_box_type(box_type)
    }
    let child_cursor = @bytes.ReadCursor::from_view(
      payload,
      start + header_bytes.to_uint64(),
      limits=cursor.limits(),
    )
    self.walk_level(child_cursor, depth + 1)
  } else {
    []
  }
  { box_type, start, header_bytes, declared_size, total_size, children, }
}

///|
/// 木を深さ優先（pre-order、深さはトップレベルを 1）で平坦化する。
///
/// dump と差分比較の共通表現として使う。
pub fn flatten_box_tree(nodes : Array[BoxNode]) -> Array[(Int32, BoxNode)] {
  let out : Array[(Int32, BoxNode)] = []
  flatten_box_tree_into(nodes, 1, out)
  out
}

///|
fn flatten_box_tree_into(
  nodes : Array[BoxNode],
  depth : Int32,
  out : Array[(Int32, BoxNode)],
) -> Unit {
  for node in nodes {
    out.push((depth, node))
    flatten_box_tree_into(node.children(), depth + 1, out)
  }
}
