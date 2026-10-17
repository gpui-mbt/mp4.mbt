///|
test "non zero u16 encodes and decodes a 16-bit value" {
  let value = @bytes.NonZeroU16::new(42U).unwrap()
  let bytes = @bytes.encode_to_bytes(value)
  inspect(bytes == b"\x00\x2A", content="true")
  let cursor = @bytes.ReadCursor::new(bytes)
  let decoded : @bytes.NonZeroU16 = @bytes.decode_from(cursor)
  inspect(decoded == value, content="true")
  inspect(cursor.is_empty(), content="true")
}

///|
test "non zero u16 one and default are one" {
  inspect(@bytes.NonZeroU16::new(0U) is None, content="true")
  inspect(@bytes.NonZeroU16::one().get(), content="1")
  inspect(
    @bytes.NonZeroU16::default() == @bytes.NonZeroU16::one(),
    content="true",
  )
  inspect(@bytes.NonZeroU16::new(0xFFFFU) is Some(_), content="true")
  inspect(@bytes.NonZeroU16::new(0x1_0000U) is None, content="true")
}

///|
test "non zero u16 decode rejects zero with the upstream reason" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00")
  let result : @bytes.NonZeroU16? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Expected a non-zero integer, but got 0")
      None
    }
  } noraise {
    value => Some(value)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
