///|
test "stsc round trips run-length entries" {
  let stsc = @boxes.StscBox::new([
    @boxes.StscEntry::new(
      @bytes.NonZeroU32::one(),
      2U,
      @bytes.NonZeroU32::one(),
    ),
    @boxes.StscEntry::new(
      @bytes.NonZeroU32::new(3U).unwrap(),
      3U,
      @bytes.NonZeroU32::new(2U).unwrap(),
    ),
  ])
  let encoded = @bytes.encode_to_bytes(stsc)
  // header (8) + full box header (4) + entry_count (4) + 2 entries (24)
  inspect(encoded.length(), content="40")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.StscBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == stsc, content="true")
  inspect(decoded.entries[1].first_chunk.get(), content="3")
  inspect(decoded.entries[1].sample_per_chunk, content="3")
  inspect(decoded.entries[1].sample_description_index.get(), content="2")
}

///|
test "stsc with no entries encodes the empty table" {
  let stsc = @boxes.StscBox::new([])
  let encoded = @bytes.encode_to_bytes(stsc)
  inspect(
    encoded == b"\x00\x00\x00\x10stsc\x00\x00\x00\x00\x00\x00\x00\x00",
    content="true",
  )
  let decoded : @boxes.StscBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == stsc, content="true")
}

///|
test "stsc decode rejects a zero first_chunk" {
  let bytes = test_box_bytes(
    b"stsc",
    b"\x00\x00\x00\x00" +
    b"\x00\x00\x00\x01" +
    b"\x00\x00\x00\x00" +
    b"\x00\x00\x00\x02" +
    b"\x00\x00\x00\x01",
  )
  let cursor = @bytes.ReadCursor::new(bytes)
  let result : @boxes.StscBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Expected a non-zero integer, but got 0")
      None
    }
  } noraise {
    stsc => Some(stsc)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "stsc decode rejects a zero sample_description_index" {
  let bytes = test_box_bytes(
    b"stsc",
    b"\x00\x00\x00\x00" +
    b"\x00\x00\x00\x01" +
    b"\x00\x00\x00\x01" +
    b"\x00\x00\x00\x02" +
    b"\x00\x00\x00\x00",
  )
  let cursor = @bytes.ReadCursor::new(bytes)
  let result : @boxes.StscBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Expected a non-zero integer, but got 0")
      None
    }
  } noraise {
    stsc => Some(stsc)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
