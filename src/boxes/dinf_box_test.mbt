///|
test "dinf local file round trips" {
  let dinf = @boxes.DinfBox::local_file()
  let bytes = @bytes.encode_to_bytes(dinf)
  let cursor = @bytes.ReadCursor::new(bytes)
  let decoded : @boxes.DinfBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == dinf, content="true")
  inspect(decoded.dref_box.url_box is Some(_), content="true")
  inspect(@box.BaseBox::box_type(decoded).to_string(), content="dinf")
  inspect(@box.BaseBox::children(decoded).length(), content="1")
}

///|
test "dinf requires dref" {
  let cursor = @bytes.ReadCursor::new(test_box_bytes(b"dinf", b""))
  let result : @boxes.DinfBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Missing mandatory 'dref' box in 'dinf' box")
      None
    }
  } noraise {
    dinf => Some(dinf)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "dinf keeps the first dref and retains later ones as unknown" {
  let dref = @bytes.encode_to_bytes(@boxes.DrefBox::local_file())
  let bytes = test_box_bytes(b"dinf", dref + dref)
  let decoded : @boxes.DinfBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.dref_box.url_box is Some(_), content="true")
  inspect(decoded.unknown_boxes.length(), content="1")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="dref")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="2")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="dref")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="dref")
  inspect(children[1].is_unknown_box(), content="true")
}

///|
test "dinf retains unknown children in order" {
  let dref = @bytes.encode_to_bytes(@boxes.DrefBox::local_file())
  let other = test_box_bytes(b"yyyy", b"\x01")
  let bytes = test_box_bytes(b"dinf", test_unknown_bytes() + dref + other)
  let decoded : @boxes.DinfBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.unknown_boxes.length(), content="2")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="zzzz")
  inspect(decoded.unknown_boxes[1].box_type.to_string(), content="yyyy")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="3")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="dref")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="zzzz")
  inspect(@box.BaseBox::box_type(children[2]).to_string(), content="yyyy")
}
