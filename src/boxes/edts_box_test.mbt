///|
test "edts without elst round trips" {
  let edts = @boxes.EdtsBox::new(None, [])
  let encoded = @bytes.encode_to_bytes(edts)
  inspect(encoded == b"\x00\x00\x00\x08edts", content="true")
  let decoded : @boxes.EdtsBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded.elst_box is None, content="true")
  inspect(decoded == edts, content="true")
  inspect(@box.BaseBox::box_type(decoded).to_string(), content="edts")
  inspect(@box.BaseBox::children(decoded).length(), content="0")
}

///|
test "edts with elst round trips" {
  let elst = @boxes.ElstBox::new([
    @boxes.ElstEntry::new(1000UL, -1L, @bytes.FixedPointNumber::new(1, 0)),
  ])
  let edts = @boxes.EdtsBox::new(Some(elst), [])
  let bytes = @bytes.encode_to_bytes(edts)
  let cursor = @bytes.ReadCursor::new(bytes)
  let decoded : @boxes.EdtsBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == edts, content="true")
  inspect(@box.BaseBox::children(decoded).length(), content="1")
}

///|
test "edts keeps the first elst and retains later ones as unknown" {
  let elst = @bytes.encode_to_bytes(@boxes.ElstBox::new([]))
  let bytes = test_box_bytes(b"edts", elst + elst)
  let decoded : @boxes.EdtsBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.elst_box is Some(_), content="true")
  inspect(decoded.unknown_boxes.length(), content="1")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="elst")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="2")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="elst")
  inspect(children[1].is_unknown_box(), content="true")
}

///|
test "edts retains unknown children in order" {
  let elst = @bytes.encode_to_bytes(@boxes.ElstBox::new([]))
  let other = test_box_bytes(b"yyyy", b"\x01")
  let bytes = test_box_bytes(b"edts", test_unknown_bytes() + elst + other)
  let decoded : @boxes.EdtsBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.unknown_boxes.length(), content="2")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="zzzz")
  inspect(decoded.unknown_boxes[1].box_type.to_string(), content="yyyy")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="3")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="elst")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="zzzz")
  inspect(@box.BaseBox::box_type(children[2]).to_string(), content="yyyy")
}
