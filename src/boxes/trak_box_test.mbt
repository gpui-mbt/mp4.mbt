///|
test "trak round trips with edts and mdia" {
  let trak = @boxes.TrakBox::new(
    test_tkhd(),
    Some(@boxes.EdtsBox::new(None, [])),
    test_mdia(),
    [],
  )
  let bytes = @bytes.encode_to_bytes(trak)
  let cursor = @bytes.ReadCursor::new(bytes)
  let decoded : @boxes.TrakBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == trak, content="true")
  inspect(@box.BaseBox::box_type(decoded).to_string(), content="trak")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="3")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="tkhd")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="edts")
  inspect(@box.BaseBox::box_type(children[2]).to_string(), content="mdia")
}

///|
test "trak requires tkhd" {
  let bytes = test_box_bytes(b"trak", @bytes.encode_to_bytes(test_mdia()))
  let cursor = @bytes.ReadCursor::new(bytes)
  let result : @boxes.TrakBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Missing mandatory 'tkhd' box in 'trak' box")
      None
    }
  } noraise {
    trak => Some(trak)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "trak requires mdia" {
  let bytes = test_box_bytes(b"trak", @bytes.encode_to_bytes(test_tkhd()))
  let cursor = @bytes.ReadCursor::new(bytes)
  let result : @boxes.TrakBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Missing mandatory 'mdia' box in 'trak' box")
      None
    }
  } noraise {
    trak => Some(trak)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "trak keeps the first tkhd and retains later ones as unknown" {
  let tkhd = @bytes.encode_to_bytes(test_tkhd())
  let mdia = @bytes.encode_to_bytes(test_mdia())
  let bytes = test_box_bytes(b"trak", tkhd + tkhd + mdia)
  let decoded : @boxes.TrakBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.unknown_boxes.length(), content="1")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="tkhd")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="3")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="tkhd")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="mdia")
  inspect(@box.BaseBox::box_type(children[2]).to_string(), content="tkhd")
  inspect(children[2].is_unknown_box(), content="true")
}

///|
test "trak retains unknown children in order" {
  let tkhd = @bytes.encode_to_bytes(test_tkhd())
  let mdia = @bytes.encode_to_bytes(test_mdia())
  let other = test_box_bytes(b"yyyy", b"\x01")
  let bytes = test_box_bytes(
    b"trak",
    test_unknown_bytes() + tkhd + mdia + other,
  )
  let decoded : @boxes.TrakBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.unknown_boxes.length(), content="2")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="zzzz")
  inspect(decoded.unknown_boxes[1].box_type.to_string(), content="yyyy")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="4")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="tkhd")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="mdia")
  inspect(@box.BaseBox::box_type(children[2]).to_string(), content="zzzz")
  inspect(@box.BaseBox::box_type(children[3]).to_string(), content="yyyy")
}
