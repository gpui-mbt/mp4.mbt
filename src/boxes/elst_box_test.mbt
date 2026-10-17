///|
test "elst version 0 round trips entries including -1 media time" {
  let elst = @boxes.ElstBox::new([
    @boxes.ElstEntry::new(1000UL, -1L, @bytes.FixedPointNumber::new(1, 0)),
  ])
  let encoded = @bytes.encode_to_bytes(elst)
  inspect(encoded[8].to_uint(), content="0")
  inspect(encoded.length(), content="28")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.ElstBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == elst, content="true")
  inspect(decoded.entries.length(), content="1")
  inspect(decoded.entries[0].edit_duration, content="1000")
  inspect(decoded.entries[0].media_time, content="-1")
  inspect(decoded.entries[0].media_rate.integer(), content="1")
}

///|
test "elst uses version 1 above the 32-bit signed ranges" {
  let elst = @boxes.ElstBox::new([
    @boxes.ElstEntry::new(
      4294967296UL,
      -2147483649L,
      @bytes.FixedPointNumber::new(1, 0),
    ),
  ])
  let encoded = @bytes.encode_to_bytes(elst)
  inspect(encoded[8].to_uint(), content="1")
  inspect(encoded.length(), content="36")
  let decoded : @boxes.ElstBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded.entries[0].edit_duration, content="4294967296")
  inspect(decoded.entries[0].media_time, content="-2147483649")
  inspect(decoded == elst, content="true")
}

///|
test "elst keeps version 0 at the 32-bit signed limits" {
  let elst = @boxes.ElstBox::new([
    @boxes.ElstEntry::new(
      4294967295UL,
      2147483647L,
      @bytes.FixedPointNumber::new(1, 0),
    ),
    @boxes.ElstEntry::new(0UL, -2147483648L, @bytes.FixedPointNumber::new(0, 0)),
  ])
  let encoded = @bytes.encode_to_bytes(elst)
  inspect(encoded[8].to_uint(), content="0")
  let decoded : @boxes.ElstBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == elst, content="true")
  inspect(decoded.entries[0].media_time, content="2147483647")
  inspect(decoded.entries[1].media_time, content="-2147483648")
}

///|
test "elst with no entries is an empty list" {
  let elst = @boxes.ElstBox::new([])
  let encoded = @bytes.encode_to_bytes(elst)
  inspect(
    encoded == b"\x00\x00\x00\x10elst\x00\x00\x00\x00\x00\x00\x00\x00",
    content="true",
  )
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.ElstBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded.entries.length(), content="0")
  inspect(decoded == elst, content="true")
}
