///|
test "free decode and encode round trips" {
  let bytes = b"\x00\x00\x00\x0Cfree\x00\x00\x00\x00"
  let cursor = @bytes.ReadCursor::new(bytes)
  let free : @boxes.FreeBox = @bytes.decode_from(cursor)
  inspect(free.payload.length(), content="4")
  inspect(cursor.is_empty(), content="true")
  inspect(@bytes.encode_to_bytes(free) == bytes, content="true")
  inspect(free.is_unknown_box(), content="false")
  inspect(
    @box.BaseBox::box_type(free) ==
    @bytes.BoxType::Normal(@bytes.FourCC::from_string("free")),
    content="true",
  )
  inspect(@box.BaseBox::children(free).length(), content="0")
}

///|
test "free with an empty payload round trips" {
  let bytes = b"\x00\x00\x00\x08free"
  let cursor = @bytes.ReadCursor::new(bytes)
  let free : @boxes.FreeBox = @bytes.decode_from(cursor)
  inspect(free.payload.length(), content="0")
  inspect(cursor.is_empty(), content="true")
  inspect(@bytes.encode_to_bytes(free) == bytes, content="true")
}

///|
test "free decode rejects another box type and rolls back" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x08mdat")
  let result : @boxes.FreeBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, box_type~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Expected box type `free`, but got `mdat`")
      inspect(
        box_type ==
        Some(@bytes.BoxType::Normal(@bytes.FourCC::from_string("free"))),
        content="true",
      )
      None
    }
  } noraise {
    free => Some(free)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "free with a size zero payload extends to the end" {
  let bytes = b"\x00\x00\x00\x00free\x00\x00"
  let cursor = @bytes.ReadCursor::new(bytes)
  let free : @boxes.FreeBox = @bytes.decode_from(cursor)
  inspect(free.payload.length(), content="2")
  inspect(cursor.is_empty(), content="true")
}
