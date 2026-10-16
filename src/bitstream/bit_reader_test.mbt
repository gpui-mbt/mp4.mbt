///|
test "reads MSB first bit by bit" {
  let reader = @bitstream.BitReader::new(b"\xB2")
  inspect(reader.read_bit(), content="1")
  inspect(reader.read_bit(), content="0")
  inspect(reader.read_bit(), content="1")
  inspect(reader.read_bit(), content="1")
  inspect(reader.read_bit(), content="0")
  inspect(reader.read_bit(), content="0")
  inspect(reader.read_bit(), content="1")
  inspect(reader.read_bit(), content="0")
  inspect(reader.remaining_bits(), content="0")
  inspect(reader.is_byte_aligned(), content="true")
  inspect(reader.position(), content="8")
}

///|
test "read_bits spans byte boundaries" {
  let reader = @bitstream.BitReader::new(b"\x12\x34")
  inspect(reader.read_bits(4), content="1")
  inspect(reader.read_bits(8), content="35")
  inspect(reader.read_bits(4), content="4")
  inspect(reader.remaining_bits(), content="0")
}

///|
test "read_bits accepts zero width without advancing" {
  let reader = @bitstream.BitReader::new(b"\x01")
  inspect(reader.read_bits(0), content="0")
  inspect(reader.position(), content="0")
  inspect(reader.read_bits(8), content="1")
  inspect(reader.remaining_bits(), content="0")
}

///|
test "read_bits64 reads 64 bit values" {
  let reader = @bitstream.BitReader::new(b"\xDE\xAD\xBE\xEF\xCA\xFE\xBA\xBE")
  inspect(reader.read_bits64(64) == 0xDEADBEEFCAFEBABEUL, content="true")
  inspect(reader.remaining_bits(), content="0")
}

///|
test "read_bits rejects widths above 32" {
  let reader = @bitstream.BitReader::new(b"\x01")
  try reader.read_bits(33) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(offset)
      ignore(loc)
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="bit width must be 0..=32: 33")
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
}

///|
test "truncated bit reads fail with InvalidInput and do not advance" {
  let reader = @bitstream.BitReader::new(b"\x01")
  try reader.read_bits(9) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(offset)
      ignore(loc)
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="bit stream is truncated: required 9 bits, but only 8 bits remain",
      )
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
  inspect(reader.position(), content="0")
}

///|
test "skip_bits and byte_align move without reading" {
  let reader = @bitstream.BitReader::new(b"\xF0\x0F")
  reader.skip_bits(4)
  inspect(reader.position(), content="4")
  inspect(reader.is_byte_aligned(), content="false")
  reader.byte_align()
  inspect(reader.position(), content="8")
  inspect(reader.is_byte_aligned(), content="true")
  inspect(reader.read_bits(8), content="15")
  inspect(reader.remaining_bits(), content="0")
}

///|
test "skip_bits past the end fails without advancing" {
  let reader = @bitstream.BitReader::new(b"\x00")
  try reader.skip_bits(9) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(reason)
      ignore(offset)
      ignore(loc)
      inspect(kind.to_string(), content="InvalidInput")
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
  inspect(reader.position(), content="0")
}
