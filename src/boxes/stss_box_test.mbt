///|
test "stss round trips sample numbers" {
  let stss = @boxes.StssBox::new([
    @bytes.NonZeroU32::one(),
    @bytes.NonZeroU32::new(5U).unwrap(),
  ])
  let encoded = @bytes.encode_to_bytes(stss)
  // header (8) + full box header (4) + entry_count (4) + 2 numbers (8)
  inspect(encoded.length(), content="24")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.StssBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == stss, content="true")
  inspect(decoded.sample_numbers[1].get(), content="5")
}

///|
test "stss with no numbers is an empty table" {
  let stss = @boxes.StssBox::new([])
  let encoded = @bytes.encode_to_bytes(stss)
  inspect(
    encoded == b"\x00\x00\x00\x10stss\x00\x00\x00\x00\x00\x00\x00\x00",
    content="true",
  )
  let decoded : @boxes.StssBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == stss, content="true")
}

///|
test "stss decode rejects a zero sample number" {
  let bytes = test_box_bytes(
    b"stss",
    b"\x00\x00\x00\x00" + b"\x00\x00\x00\x01" + b"\x00\x00\x00\x00",
  )
  let cursor = @bytes.ReadCursor::new(bytes)
  let result : @boxes.StssBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Expected a non-zero integer, but got 0")
      None
    }
  } noraise {
    stss => Some(stss)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
