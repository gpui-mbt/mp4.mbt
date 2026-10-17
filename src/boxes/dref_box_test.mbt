///|
test "dref local file round trips canonically" {
  let dref = @boxes.DrefBox::local_file()
  let bytes = @bytes.encode_to_bytes(dref)
  inspect(
    bytes ==
    b"\x00\x00\x00\x1Cdref\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x0Curl \x00\x00\x00\x01",
    content="true",
  )
  let cursor = @bytes.ReadCursor::new(bytes)
  let decoded : @boxes.DrefBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == dref, content="true")
  inspect(decoded.url_box is Some(_), content="true")
  inspect(decoded.unknown_boxes.length(), content="0")
}

///|
test "dref with no entries encodes a zero entry count" {
  let dref = @boxes.DrefBox::new(None, [])
  let encoded = @bytes.encode_to_bytes(dref)
  inspect(
    encoded == b"\x00\x00\x00\x10dref\x00\x00\x00\x00\x00\x00\x00\x00",
    content="true",
  )
  let decoded : @boxes.DrefBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == dref, content="true")
}

///|
test "dref reads exactly entry_count children and ignores the rest" {
  let url = b"\x00\x00\x00\x0Curl \x00\x00\x00\x01"
  let payload = b"\x00\x00\x00\x00" +
    test_u32(1U) +
    url +
    test_box_bytes(b"zzzz", b"\xAA")
  let bytes = test_box_bytes(b"dref", payload)
  let cursor = @bytes.ReadCursor::new(bytes)
  let decoded : @boxes.DrefBox = @bytes.decode_from(cursor)
  // entry_count を超える子は読まずに捨てるが、dref ボックス全体は消費する。
  inspect(cursor.is_empty(), content="true")
  inspect(decoded.url_box is Some(_), content="true")
  inspect(decoded.unknown_boxes.length(), content="0")
}

///|
test "dref keeps only the first url and retains the second as unknown" {
  let url = b"\x00\x00\x00\x0Curl \x00\x00\x00\x01"
  let payload = b"\x00\x00\x00\x00" + test_u32(2U) + url + url
  let bytes = test_box_bytes(b"dref", payload)
  let decoded : @boxes.DrefBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.url_box is Some(_), content="true")
  inspect(decoded.unknown_boxes.length(), content="1")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="url ")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="2")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="url ")
  inspect(children[1].is_unknown_box(), content="true")
}

///|
test "dref without url round trips with a recalculated entry count" {
  let bytes = test_box_bytes(
    b"dref",
    b"\x00\x00\x00\x00" + test_u32(1U) + test_box_bytes(b"zzzz", b"\xAA"),
  )
  let decoded : @boxes.DrefBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.url_box is None, content="true")
  inspect(decoded.unknown_boxes.length(), content="1")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}
