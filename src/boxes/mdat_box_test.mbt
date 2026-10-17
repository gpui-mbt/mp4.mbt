///|
test "mdat decode records the payload range with the base offset" {
  let cursor = @bytes.ReadCursor::with_config(
    b"\x00\x00\x00\x0Cmdat\x11\x22\x33\x44",
    4096UL,
    @bytes.ParseLimits::default(),
  )
  let mdat : @boxes.MdatBox = @bytes.decode_from(cursor)
  inspect(mdat.data_offset, content="4104")
  inspect(mdat.data_size, content="4")
  inspect(cursor.is_empty(), content="true")
  inspect(mdat.is_unknown_box(), content="false")
  inspect(
    @box.BaseBox::box_type(mdat) ==
    @bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat")),
    content="true",
  )
  inspect(@box.BaseBox::children(mdat).length(), content="0")
}

///|
test "mdat with size zero extends to the end of the buffer" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x00mdat\x11\x22\x33")
  let mdat : @boxes.MdatBox = @bytes.decode_from(cursor)
  inspect(mdat.data_offset, content="8")
  inspect(mdat.data_size, content="3")
  inspect(cursor.is_empty(), content="true")
}

///|
test "mdat keeps no payload copy under a tiny allocation limit" {
  let limits = @bytes.ParseLimits::new(max_allocation_size=16UL)
  let writer = @bytes.WriteCursor::new()
  writer.write_u32(8U + 65536U)
  writer.write_bytes(b"mdat")
  writer.write_bytes(b"\x11".repeat(65536))
  let cursor = @bytes.ReadCursor::with_config(writer.to_bytes(), 0UL, limits)
  let mdat : @boxes.MdatBox = @bytes.decode_from(cursor)
  inspect(mdat.data_offset, content="8")
  inspect(mdat.data_size, content="65536")
  inspect(cursor.is_empty(), content="true")
}

///|
test "mdat decode rejects another box type and rolls back" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x08free")
  let result : @boxes.MdatBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Expected box type `mdat`, but got `free`")
      None
    }
  } noraise {
    mdat => Some(mdat)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
