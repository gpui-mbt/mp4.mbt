///|
test "read unsigned widths are big endian" {
  let cursor = @bytes.ReadCursor::new(b"\x01\x02\x03\x04\x05\x06\x07\x08")
  inspect(cursor.read_u8(), content="1")
  inspect(cursor.read_u16(), content="515")
  inspect(cursor.read_u24(), content="263430")
  inspect(cursor.read_u16(), content="1800")
  inspect(cursor.position(), content="8")
  inspect(cursor.remaining(), content="0")
  inspect(cursor.is_empty(), content="true")
}

///|
test "read u32 and u64 keep 64-bit precision" {
  let cursor = @bytes.ReadCursor::new(b"\x12\x34\x56\x78")
  inspect(cursor.read_u32(), content="305419896")
  let cursor = @bytes.ReadCursor::new(
    b"\x00\x20\x00\x00\x00\x00\x00\x01\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF",
  )
  inspect(cursor.read_u64(), content="9007199254740993")
  inspect(cursor.read_u64(), content="18446744073709551615")
}

///|
test "read signed values sign extend" {
  let cursor = @bytes.ReadCursor::new(
    b"\xFF\x80\x00\xFF\xFF\xFF\xFE\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFE",
  )
  inspect(cursor.read_i8(), content="-1")
  inspect(cursor.read_i16(), content="-32768")
  inspect(cursor.read_i32(), content="-2")
  inspect(cursor.read_i64(), content="-2")
  inspect(cursor.is_empty(), content="true")
}

///|
test "read_fixed_16_16 and read_fixed_8_8 keep integer and fraction" {
  let cursor = @bytes.ReadCursor::new(b"\xFF\x80\xFF\x80")
  let wide = cursor.read_fixed_16_16()
  inspect(wide.integer(), content="-128")
  inspect(wide.fraction(), content="65408")
  let cursor = @bytes.ReadCursor::new(b"\xFF\x80")
  let narrow = cursor.read_fixed_8_8()
  inspect(narrow.integer(), content="-1")
  inspect(narrow.fraction(), content="128")
}

///|
test "read_fourcc reads four raw bytes" {
  let cursor = @bytes.ReadCursor::new(b"ftyp")
  inspect(cursor.read_fourcc().to_string(), content="ftyp")
  inspect(cursor.remaining(), content="0")
}

///|
test "short read fails with InsufficientBuffer and does not advance" {
  let cursor = @bytes.ReadCursor::new(b"\x01")
  try cursor.read_u16() catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(loc)
      inspect(kind.to_string(), content="InsufficientBuffer")
      inspect(reason, content="required 2 bytes, but only 1 bytes available")
      inspect(offset == Some(0UL), content="true")
    }
  } noraise {
    _ => fail("expected InsufficientBuffer")
  }
  inspect(cursor.position(), content="0")
  inspect(cursor.remaining(), content="1")
}

///|
test "zero length buffer reports empty input for one byte" {
  let cursor = @bytes.ReadCursor::new(b"")
  try cursor.read_u8() catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(loc)
      ignore(offset)
      inspect(kind.to_string(), content="InsufficientBuffer")
      inspect(reason, content="required 1 bytes, but only 0 bytes available")
    }
  } noraise {
    _ => fail("expected InsufficientBuffer")
  }
}

///|
test "error offset is base offset plus position" {
  let cursor = @bytes.ReadCursor::with_config(
    b"\x01\x02",
    100UL,
    @bytes.ParseLimits::default(),
  )
  cursor.skip(1)
  try cursor.read_u32() catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(kind)
      ignore(reason)
      ignore(loc)
      inspect(offset == Some(101UL), content="true")
    }
  } noraise {
    _ => fail("expected InsufficientBuffer")
  }
}

///|
test "skip past the end fails without advancing" {
  let cursor = @bytes.ReadCursor::new(b"\x01\x02")
  try cursor.skip(3) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(reason)
      ignore(loc)
      inspect(kind.to_string(), content="InsufficientBuffer")
      ignore(offset)
    }
  } noraise {
    _ => fail("expected InsufficientBuffer")
  }
  inspect(cursor.position(), content="0")
}

///|
test "rewind_to restores the position and rejects out of range values" {
  let cursor = @bytes.ReadCursor::new(b"\x01\x02")
  ignore(cursor.read_u8())
  cursor.rewind_to(0)
  inspect(cursor.position(), content="0")
  try cursor.rewind_to(3) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(reason)
      ignore(offset)
      ignore(loc)
      inspect(kind.to_string(), content="InvalidInput")
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
}

///|
test "read_bytes copies while read_bytes_view does not consume the original" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x01\x02\x03")
  let view = cursor.read_bytes_view(2)
  inspect(view.length(), content="2")
  inspect(view[0].to_uint(), content="0")
  inspect(view[1].to_uint(), content="1")
  inspect(cursor.position(), content="2")
  let bytes = cursor.read_bytes(2)
  debug_inspect(bytes, content="<Bytes: [0x02, 0x03]>")
  inspect(cursor.is_empty(), content="true")
}

///|
test "read_remaining variants consume the rest" {
  let cursor = @bytes.ReadCursor::new(b"\xAA\xBB")
  cursor.skip(1)
  let view = cursor.read_remaining_view()
  inspect(view.length(), content="1")
  inspect(cursor.is_empty(), content="true")
  let cursor = @bytes.ReadCursor::new(b"\xAA\xBB")
  debug_inspect(cursor.read_remaining(), content="<Bytes: [0xaa, 0xbb]>")
  inspect(cursor.is_empty(), content="true")
}

///|
test "sub_cursor inherits base offset and limits without copying" {
  let limits = @bytes.ParseLimits::new(max_allocation_size=2UL)
  let cursor = @bytes.ReadCursor::with_config(b"\xAA\xBB\xCC", 10UL, limits)
  let sub = cursor.sub_cursor(2)
  inspect(sub.base_offset(), content="10")
  inspect(sub.offset(), content="10")
  inspect(sub.remaining(), content="2")
  inspect(sub.limits().max_allocation_size(), content="2")
  inspect(cursor.position(), content="2")
  inspect(cursor.remaining(), content="1")
  inspect(sub.read_u8(), content="170")
  inspect(sub.read_u8(), content="187")
  inspect(sub.position(), content="2")
}

///|
test "read_bytes enforces max_allocation_size without advancing" {
  let limits = @bytes.ParseLimits::new(max_allocation_size=3UL)
  let cursor = @bytes.ReadCursor::with_config(b"\x01\x02\x03\x04", 0UL, limits)
  try cursor.read_bytes(4) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(offset)
      ignore(loc)
      inspect(kind.to_string(), content="Unsupported")
      inspect(
        reason,
        content="allocation of 4 bytes exceeds ParseLimits.max_allocation_size=3",
      )
    }
  } noraise {
    _ => fail("expected Unsupported")
  }
  inspect(cursor.position(), content="0")
  let view = cursor.read_bytes_view(4)
  inspect(view.length(), content="4")
}

///|
test "read_bytes_view is bounds checked even though it does not allocate" {
  let cursor = @bytes.ReadCursor::new(b"\x01")
  try cursor.read_bytes_view(2) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(reason)
      ignore(offset)
      ignore(loc)
      inspect(kind.to_string(), content="InsufficientBuffer")
    }
  } noraise {
    _ => fail("expected InsufficientBuffer")
  }
  inspect(cursor.position(), content="0")
}

///|
test "negative read lengths are rejected as InvalidInput" {
  let cursor = @bytes.ReadCursor::new(b"\x01")
  try cursor.skip(-1) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(offset)
      ignore(loc)
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="read length must be non-negative: -1")
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
}
