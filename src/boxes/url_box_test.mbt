///|
test "url local file decodes and encodes self contained" {
  let bytes = b"\x00\x00\x00\x0Curl \x00\x00\x00\x01"
  let cursor = @bytes.ReadCursor::new(bytes)
  let box : @boxes.UrlBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(box.location is None, content="true")
  inspect(box == @boxes.UrlBox::local_file(), content="true")
  inspect(@bytes.encode_to_bytes(box) == bytes, content="true")
  inspect(@box.BaseBox::box_type(box).to_string(), content="url ")
  inspect(@box.BaseBox::children(box).length(), content="0")
}

///|
test "url with a location round trips the string" {
  let payload = b"\x00\x00\x00\x00" + b"http://example.com\x00"
  let bytes = test_box_bytes(b"url ", payload)
  let cursor = @bytes.ReadCursor::new(bytes)
  let box : @boxes.UrlBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  match box.location {
    Some(location) => inspect(location.get(), content="http://example.com")
    None => fail("location が得られるはず")
  }
  inspect(@bytes.encode_to_bytes(box) == bytes, content="true")
}

///|
test "url without a null terminator fails" {
  let bytes = test_box_bytes(b"url ", b"\x00\x00\x00\x00" + b"http://x")
  let cursor = @bytes.ReadCursor::new(bytes)
  let result : @boxes.UrlBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      // 上流 Utf8String::decode と同じ invalid_input。
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Null-terminated string not found")
      None
    }
  } noraise {
    box => Some(box)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "url with the self contained flag ignores payload bytes" {
  // flags bit 0 が立っている場合は文字列を読まずに捨てる（上流と同じ）。
  let bytes = test_box_bytes(b"url ", b"\x00\x00\x00\x01" + b"ignored\x00")
  let box : @boxes.UrlBox = @bytes.decode_from(@bytes.ReadCursor::new(bytes))
  inspect(box.location is None, content="true")
  inspect(
    @bytes.encode_to_bytes(box) == b"\x00\x00\x00\x0Curl \x00\x00\x00\x01",
    content="true",
  )
}
