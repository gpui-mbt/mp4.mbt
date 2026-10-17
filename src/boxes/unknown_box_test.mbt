///|
test "unknown box keeps the payload and round trips" {
  let bytes = b"\x00\x00\x00\x0Azzzz\xAA\xBB"
  let cursor = @bytes.ReadCursor::new(bytes)
  let unknown : @boxes.UnknownBox = @bytes.decode_from(cursor)
  inspect(unknown.box_type.to_string(), content="zzzz")
  inspect(unknown.payload.length(), content="2")
  inspect(unknown.box_size == @box.BoxSize::U32(10U), content="true")
  inspect(cursor.is_empty(), content="true")
  inspect(@bytes.encode_to_bytes(unknown) == bytes, content="true")
  inspect(unknown.is_unknown_box(), content="true")
  inspect(@box.BaseBox::children(unknown).length(), content="0")
}

///|
test "unknown box decode rejects size zero" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x00zzzz\xAA\xBB")
  let result : @boxes.UnknownBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, box_type~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="UnknownBox does not accept size=0")
      inspect(offset == Some(0UL), content="true")
      inspect(
        box_type ==
        Some(@bytes.BoxType::Normal(@bytes.FourCC::from_string("zzzz"))),
        content="true",
      )
      None
    }
  } noraise {
    unknown => Some(unknown)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "unknown box decode_top_level accepts size zero and preserves it" {
  let bytes = b"\x00\x00\x00\x00zzzz\xAA\xBB"
  let cursor = @bytes.ReadCursor::new(bytes)
  let unknown = @boxes.UnknownBox::decode_top_level(cursor)
  inspect(unknown.box_type.to_string(), content="zzzz")
  inspect(unknown.payload.length(), content="2")
  inspect(unknown.box_size == @box.BoxSize::variable_size(), content="true")
  inspect(cursor.is_empty(), content="true")
  inspect(@bytes.encode_to_bytes(unknown) == bytes, content="true")
}

///|
test "unknown box largesize is preserved by encode" {
  let bytes = b"\x00\x00\x00\x01zzzz\x00\x00\x00\x00\x00\x00\x00\x12\xAA\xBB"
  let cursor = @bytes.ReadCursor::new(bytes)
  let unknown : @boxes.UnknownBox = @bytes.decode_from(cursor)
  inspect(unknown.box_size == @box.BoxSize::U64(18UL), content="true")
  inspect(unknown.payload.length(), content="2")
  inspect(cursor.is_empty(), content="true")
  inspect(@bytes.encode_to_bytes(unknown) == bytes, content="true")
}

///|
test "unknown box decode_top_level stops at the buffer end" {
  let bytes = b"\x00\x00\x00\x0Azzzz\xAA\xBB" + b"\x00\x00\x00\x08free"
  let cursor = @bytes.ReadCursor::new(bytes)
  let unknown = @boxes.UnknownBox::decode_top_level(cursor)
  inspect(unknown.payload.length(), content="2")
  inspect(cursor.position(), content="10")
  let free : @boxes.FreeBox = @bytes.decode_from(cursor)
  inspect(free.payload.length(), content="0")
  inspect(cursor.is_empty(), content="true")
}

///|
test "unknown box payload respects the allocation limit" {
  let limits = @bytes.ParseLimits::new(max_allocation_size=4UL)
  let cursor = @bytes.ReadCursor::with_config(
    b"\x00\x00\x00\x0Ezzzz\xAA\xBB\xCC\xDD\xEE\xFF", 0UL, limits,
  )
  let result : @boxes.UnknownBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, box_type~, ..) => {
      inspect(kind.to_string(), content="Unsupported")
      inspect(
        reason,
        content="allocation of 6 bytes exceeds ParseLimits.max_allocation_size=4",
      )
      inspect(
        box_type ==
        Some(@bytes.BoxType::Normal(@bytes.FourCC::from_string("zzzz"))),
        content="true",
      )
      None
    }
  } noraise {
    unknown => Some(unknown)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
