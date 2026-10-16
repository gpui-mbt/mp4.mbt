///|
test "write unsigned widths big endian" {
  let writer = @bytes.WriteCursor::new()
  writer.write_u8(0x12)
  writer.write_u16(0x3456)
  writer.write_u24(0x789ABC)
  writer.write_u32(0xDEF01234)
  writer.write_u64(0xFFFFFFFFFFFFFFFFUL)
  inspect(
    writer.to_bytes() ==
    b"\x12\x34\x56\x78\x9A\xBC\xDE\xF0\x12\x34\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF",
    content="true",
  )
  inspect(writer.position(), content="18")
}

///|
test "write truncates values to the written width" {
  let writer = @bytes.WriteCursor::new()
  writer.write_u8(0x123)
  writer.write_u16(0x12345)
  debug_inspect(writer.to_bytes(), content="<Bytes: [0x23, 0x23, 0x45]>")
}

///|
test "write signed values use two's complement" {
  let writer = @bytes.WriteCursor::new()
  writer.write_i8(-1)
  writer.write_i16(-32768)
  writer.write_i32(-2)
  writer.write_i64(-2L)
  inspect(
    writer.to_bytes() ==
    b"\xFF\x80\x00\xFF\xFF\xFF\xFE\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFE",
    content="true",
  )
}

///|
test "write_fixed_16_16 and write_fixed_8_8" {
  let writer = @bytes.WriteCursor::new()
  writer.write_fixed_16_16(@bytes.FixedPointNumber::new(-1, 0x8000))
  writer.write_fixed_8_8(@bytes.FixedPointNumber::new(-1, 0x80))
  debug_inspect(
    writer.to_bytes(),
    content="<Bytes: [0xff, 0xff, 0x80, 0x00, 0xff, 0x80]>",
  )
}

///|
test "write_fourcc and write_bytes" {
  let writer = @bytes.WriteCursor::new()
  writer.write_fourcc(@bytes.FourCC::from_string("ftyp"))
  writer.write_bytes(b"\x00\x01")
  writer.write_bytes_view(b"\x02"[:])
  debug_inspect(
    writer.to_bytes(),
    content="<Bytes: [0x66, 0x74, 0x79, 0x70, 0x00, 0x01, 0x02]>",
  )
}

///|
test "write then read roundtrip preserves values" {
  let writer = @bytes.WriteCursor::new()
  writer.write_u64(9007199254740993UL)
  writer.write_i64(-5L)
  writer.write_fixed_16_16(@bytes.FixedPointNumber::new(-3, 0x2000))
  writer.write_fourcc(@bytes.FourCC::from_string("abcd"))
  writer.write_bytes(b"\xDE\xAD")
  let reader = @bytes.ReadCursor::new(writer.to_bytes())
  inspect(reader.read_u64(), content="9007199254740993")
  inspect(reader.read_i64(), content="-5")
  let fixed = reader.read_fixed_16_16()
  inspect(fixed.integer(), content="-3")
  inspect(fixed.fraction(), content="8192")
  inspect(reader.read_fourcc().to_string(), content="abcd")
  debug_inspect(reader.read_remaining(), content="<Bytes: [0xde, 0xad]>")
}

///|
test "reset clears the writer" {
  let writer = @bytes.WriteCursor::new()
  writer.write_u32(0x12345678)
  inspect(writer.position(), content="4")
  writer.reset()
  inspect(writer.position(), content="0")
  inspect(writer.to_bytes().length(), content="0")
}
