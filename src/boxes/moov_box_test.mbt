///|
test "moov without tracks round trips" {
  let moov = @boxes.MoovBox::new(test_mvhd(), [], [])
  let bytes = @bytes.encode_to_bytes(moov)
  let cursor = @bytes.ReadCursor::new(bytes)
  let decoded : @boxes.MoovBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded.trak_boxes.length(), content="0")
  inspect(decoded == moov, content="true")
  inspect(@box.BaseBox::box_type(decoded).to_string(), content="moov")
  inspect(@box.BaseBox::children(decoded).length(), content="1")
}

///|
test "moov requires mvhd and rewinds the cursor on failure" {
  let cursor = @bytes.ReadCursor::new(test_box_bytes(b"moov", b""))
  let result : @boxes.MoovBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Missing mandatory 'mvhd' box in 'moov' box")
      None
    }
  } noraise {
    moov => Some(moov)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "moov keeps the first mvhd and retains later ones as unknown" {
  let mvhd = @bytes.encode_to_bytes(test_mvhd())
  let bytes = test_box_bytes(b"moov", mvhd + mvhd)
  let decoded : @boxes.MoovBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.mvhd_box == test_mvhd(), content="true")
  inspect(decoded.unknown_boxes.length(), content="1")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="mvhd")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="2")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="mvhd")
  inspect(children[1].is_unknown_box(), content="true")
}

///|
test "moov retains unknown children in order and returns typed children first" {
  let mvhd = @bytes.encode_to_bytes(test_mvhd())
  let trak = @bytes.encode_to_bytes(test_trak())
  let other = test_box_bytes(b"yyyy", b"\x01")
  let bytes = test_box_bytes(
    b"moov",
    test_unknown_bytes() + mvhd + trak + other,
  )
  let decoded : @boxes.MoovBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.unknown_boxes.length(), content="2")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="zzzz")
  inspect(decoded.unknown_boxes[1].box_type.to_string(), content="yyyy")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="4")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="mvhd")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="trak")
  inspect(@box.BaseBox::box_type(children[2]).to_string(), content="zzzz")
  inspect(@box.BaseBox::box_type(children[3]).to_string(), content="yyyy")
}

///|
test "moov keeps mvex as an unknown box until issue 0017" {
  let mvhd = @bytes.encode_to_bytes(test_mvhd())
  let mvex = test_box_bytes(b"mvex", b"")
  let bytes = test_box_bytes(b"moov", mvhd + mvex)
  let decoded : @boxes.MoovBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.unknown_boxes.length(), content="1")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="mvex")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
test "single track moov round trips with canonical 32-bit sizes" {
  let moov = test_moov()
  let encoded = @bytes.encode_to_bytes(moov)
  let size_cursor = @bytes.ReadCursor::new(encoded)
  inspect(
    size_cursor.read_u32() == encoded.length().reinterpret_as_uint(),
    content="true",
  )
  let decoded : @boxes.MoovBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == moov, content="true")
  inspect(decoded.trak_boxes.length(), content="1")
  inspect(decoded.trak_boxes[0] == test_trak(), content="true")
  // すべてのボックスのサイズフィールドが canonical な 32-bit（ヘッダー 8 バイト）。
  let nodes = @boxes.build_box_tree(@bytes.ReadCursor::new(encoded))
  for entry in @boxes.flatten_box_tree(nodes) {
    let (_, node) = entry
    inspect(node.header_bytes(), content="8")
  }
}

///|
test "root box dispatches moov to the typed variant" {
  let bytes = @bytes.encode_to_bytes(test_moov())
  let cursor = @bytes.ReadCursor::new(bytes)
  let root : @boxes.RootBox = @bytes.decode_from(cursor)
  match root {
    @boxes.RootBox::Moov(moov) => inspect(moov == test_moov(), content="true")
    _ => fail("moov が得られるはず")
  }
  inspect(cursor.is_empty(), content="true")
  inspect(root.is_unknown_box(), content="false")
  inspect(@box.BaseBox::box_type(root).to_string(), content="moov")
  inspect(@box.BaseBox::children(root).length(), content="2")
  inspect(@bytes.encode_to_bytes(root) == bytes, content="true")
}
