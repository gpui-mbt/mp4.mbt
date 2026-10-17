///|
test "root box decodes free, mdat and unknown in order" {
  let bytes = b"\x00\x00\x00\x08free" +
    b"\x00\x00\x00\x0Cmdat\x11\x22\x33\x44" +
    b"\x00\x00\x00\x0Azzzz\xAA\xBB"
  let cursor = @bytes.ReadCursor::new(bytes)
  let first : @boxes.RootBox = @bytes.decode_from(cursor)
  let second : @boxes.RootBox = @bytes.decode_from(cursor)
  let third : @boxes.RootBox = @bytes.decode_from(cursor)
  match first {
    @boxes.RootBox::Free(free) => inspect(free.payload.length(), content="0")
    _ => fail("first box must be free")
  }
  match second {
    @boxes.RootBox::Mdat(mdat) => {
      inspect(mdat.data_offset, content="16")
      inspect(mdat.data_size, content="4")
    }
    _ => fail("second box must be mdat")
  }
  match third {
    @boxes.RootBox::Unknown(unknown) => {
      inspect(unknown.box_type.to_string(), content="zzzz")
      inspect(unknown.payload.length(), content="2")
    }
    _ => fail("third box must be unknown")
  }
  inspect(cursor.is_empty(), content="true")
  inspect(first.is_unknown_box(), content="false")
  inspect(third.is_unknown_box(), content="true")
  inspect(
    @box.BaseBox::box_type(second) ==
    @bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat")),
    content="true",
  )
  inspect(@box.BaseBox::children(second).length(), content="0")
}

///|
test "root box unknown accepts size zero at the top level" {
  let bytes = b"\x00\x00\x00\x00zzzz\xAA"
  let cursor = @bytes.ReadCursor::new(bytes)
  let root : @boxes.RootBox = @bytes.decode_from(cursor)
  match root {
    @boxes.RootBox::Unknown(unknown) => {
      inspect(unknown.box_size == @box.BoxSize::variable_size(), content="true")
      inspect(unknown.payload.length(), content="1")
    }
    _ => fail("box must be unknown")
  }
  inspect(cursor.is_empty(), content="true")
  inspect(@bytes.encode_to_bytes(root) == bytes, content="true")
}

///|
test "root box encodes free and unknown but rejects mdat" {
  let free_cursor = @bytes.ReadCursor::new(
    b"\x00\x00\x00\x0Cfree\x00\x00\x00\x00",
  )
  let free : @boxes.RootBox = @bytes.decode_from(free_cursor)
  inspect(
    @bytes.encode_to_bytes(free) == b"\x00\x00\x00\x0Cfree\x00\x00\x00\x00",
    content="true",
  )
  let mdat_cursor = @bytes.ReadCursor::new(
    b"\x00\x00\x00\x0Cmdat\x11\x22\x33\x44",
  )
  let mdat : @boxes.RootBox = @bytes.decode_from(mdat_cursor)
  let result : Bytes? = try @bytes.encode_to_bytes(mdat) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="Unsupported")
      inspect(
        reason,
        content="mdat payload is not retained; write it from the source range instead",
      )
      None
    }
  } noraise {
    encoded => Some(encoded)
  }
  inspect(result is None, content="true")
}

///|
test "root box decode rejects a truncated unknown box and rolls back" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x10zzzz\xAA")
  let result : @boxes.RootBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, ..) => {
      inspect(kind.to_string(), content="InsufficientBuffer")
      None
    }
  } noraise {
    root => Some(root)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
