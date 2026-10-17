///|
test "stco round trips the u32 boundaries" {
  let stco = @boxes.StcoBox::new([0U, 0xFFFFFFFFU])
  let encoded = @bytes.encode_to_bytes(stco)
  // header (8) + full box header (4) + entry_count (4) + 2 offsets (8)
  inspect(encoded.length(), content="24")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.StcoBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == stco, content="true")
  inspect(decoded.chunk_offsets[1], content="4294967295")
}

///|
test "stco with no chunks encodes the empty table" {
  let stco = @boxes.StcoBox::new([])
  let encoded = @bytes.encode_to_bytes(stco)
  inspect(
    encoded == b"\x00\x00\x00\x10stco\x00\x00\x00\x00\x00\x00\x00\x00",
    content="true",
  )
  let decoded : @boxes.StcoBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == stco, content="true")
}

///|
test "co64 round trips offsets beyond u32" {
  let co64 = @boxes.Co64Box::new([0UL, 0x100000000UL, 0xFFFFFFFFFFFFFFFFUL])
  let encoded = @bytes.encode_to_bytes(co64)
  // header (8) + full box header (4) + entry_count (4) + 3 offsets (24)
  inspect(encoded.length(), content="40")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.Co64Box = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == co64, content="true")
  inspect(decoded.chunk_offsets[1], content="4294967296")
  inspect(decoded.chunk_offsets[2], content="18446744073709551615")
}

///|
test "co64 with no chunks encodes the empty table" {
  let co64 = @boxes.Co64Box::new([])
  let encoded = @bytes.encode_to_bytes(co64)
  inspect(
    encoded == b"\x00\x00\x00\x10co64\x00\x00\x00\x00\x00\x00\x00\x00",
    content="true",
  )
  let decoded : @boxes.Co64Box = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == co64, content="true")
}

///|
test "stco decode rejects a truncated offset table" {
  let bytes = test_box_bytes(
    b"stco",
    b"\x00\x00\x00\x00" + b"\x00\x00\x00\x02" + b"\x00\x00\x00\x01",
  )
  let cursor = @bytes.ReadCursor::new(bytes)
  let result : @boxes.StcoBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(..) => None
  } noraise {
    stco => Some(stco)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
