///|
test "write_bits packs MSB first" {
  let writer = @bitstream.BitWriter::new()
  writer.write_bits(0xB, 4)
  writer.write_bits(0x2, 4)
  debug_inspect(writer.to_bytes(), content="<Bytes: [0xb2]>")
  inspect(writer.position(), content="8")
}

///|
test "to_bytes pads the final byte with zeros" {
  let writer = @bitstream.BitWriter::new()
  writer.write_bit(1)
  debug_inspect(writer.to_bytes(), content="<Bytes: [0x80]>")
}

///|
test "skip_bits writes zeros" {
  let writer = @bitstream.BitWriter::new()
  writer.write_bits(7, 3)
  writer.skip_bits(5)
  debug_inspect(writer.to_bytes(), content="<Bytes: [0xe0]>")
}

///|
test "bit roundtrip through BitReader" {
  let writer = @bitstream.BitWriter::new()
  writer.write_bits(5, 3)
  writer.write_bits(0x123, 12)
  writer.write_bits64(0xDEADBEEFCAFEBABEUL, 64)
  writer.byte_align()
  let reader = @bitstream.BitReader::new(writer.to_bytes())
  inspect(reader.read_bits(3), content="5")
  inspect(reader.read_bits(12), content="291")
  inspect(reader.read_bits64(64) == 0xDEADBEEFCAFEBABEUL, content="true")
  inspect(reader.remaining_bits(), content="1") // byte_align が 0 で埋めた端数
}

///|
test "write_bits rejects widths above 32" {
  let writer = @bitstream.BitWriter::new()
  try writer.write_bits(0, 33) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, ..) => {
      ignore(offset)
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="bit width must be 0..=32: 33")
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
}

///|
test "reset clears pending bits and buffer" {
  let writer = @bitstream.BitWriter::new()
  writer.write_bits(0xFF, 8)
  writer.write_bit(1)
  writer.reset()
  inspect(writer.position(), content="0")
  inspect(writer.to_bytes().length(), content="0")
}
