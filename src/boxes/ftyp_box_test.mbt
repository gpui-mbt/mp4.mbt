///|
test "ftyp decode reads brands and encode round trips" {
  let bytes = b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomavc1"
  let cursor = @bytes.ReadCursor::new(bytes)
  let ftyp : @boxes.FtypBox = @bytes.decode_from(cursor)
  inspect(ftyp.major_brand.to_string(), content="isom")
  inspect(ftyp.minor_version, content="512")
  inspect(ftyp.compatible_brands.length(), content="2")
  inspect(ftyp.compatible_brands[0].to_string(), content="isom")
  inspect(ftyp.compatible_brands[1].to_string(), content="avc1")
  inspect(cursor.is_empty(), content="true")
  inspect(@bytes.encode_to_bytes(ftyp) == bytes, content="true")
  inspect(ftyp.is_unknown_box(), content="false")
  inspect(
    @box.BaseBox::box_type(ftyp) ==
    @bytes.BoxType::Normal(@bytes.FourCC::from_string("ftyp")),
    content="true",
  )
  inspect(@box.BaseBox::children(ftyp).length(), content="0")
}

///|
test "ftyp decode rejects another box type and keeps the expected type" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x08free")
  let result : @boxes.FtypBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, box_type~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Expected box type `ftyp`, but got `free`")
      inspect(
        box_type ==
        Some(@bytes.BoxType::Normal(@bytes.FourCC::from_string("ftyp"))),
        content="true",
      )
      None
    }
  } noraise {
    ftyp => Some(ftyp)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "ftyp with a partial brand fails with InsufficientBuffer" {
  let cursor = @bytes.ReadCursor::new(
    b"\x00\x00\x00\x12ftypisom\x00\x00\x02\x00ab",
  )
  let result : @boxes.FtypBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, box_type~, ..) => {
      inspect(kind.to_string(), content="InsufficientBuffer")
      inspect(reason, content="required 4 bytes, but only 2 bytes available")
      inspect(offset == Some(16UL), content="true")
      inspect(
        box_type ==
        Some(@bytes.BoxType::Normal(@bytes.FourCC::from_string("ftyp"))),
        content="true",
      )
      None
    }
  } noraise {
    ftyp => Some(ftyp)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "ftyp decoded from largesize re-encodes canonically" {
  let largesize = b"\x00\x00\x00\x01ftyp\x00\x00\x00\x00\x00\x00\x00\x20isom\x00\x00\x02\x00isomavc1"
  let cursor = @bytes.ReadCursor::new(largesize)
  let ftyp : @boxes.FtypBox = @bytes.decode_from(cursor)
  inspect(ftyp.compatible_brands.length(), content="2")
  inspect(cursor.is_empty(), content="true")
  inspect(
    @bytes.encode_to_bytes(ftyp) ==
    b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomavc1",
    content="true",
  )
}

///|
test "ftyp without compatible brands round trips" {
  let bytes = b"\x00\x00\x00\x10ftypav01\x00\x00\x00\x00"
  let cursor = @bytes.ReadCursor::new(bytes)
  let ftyp : @boxes.FtypBox = @bytes.decode_from(cursor)
  inspect(ftyp.compatible_brands.length(), content="0")
  inspect(cursor.is_empty(), content="true")
  inspect(@bytes.encode_to_bytes(ftyp) == bytes, content="true")
}

///|
test "ftyp constructed from fields encodes a canonical box" {
  let ftyp = @boxes.FtypBox::new(@bytes.FourCC::from_string("isom"), 512U, [
    @bytes.FourCC::from_string("avc1"),
  ])
  inspect(
    @bytes.encode_to_bytes(ftyp) ==
    b"\x00\x00\x00\x14ftypisom\x00\x00\x02\x00avc1",
    content="true",
  )
}

///|
test "ftyp decode stops at the box boundary" {
  let bytes = b"\x00\x00\x00\x10ftypisom\x00\x00\x00\x00" +
    b"\x00\x00\x00\x08free"
  let cursor = @bytes.ReadCursor::new(bytes)
  let ftyp : @boxes.FtypBox = @bytes.decode_from(cursor)
  inspect(ftyp.major_brand.to_string(), content="isom")
  inspect(cursor.position(), content="16")
  let free : @boxes.FreeBox = @bytes.decode_from(cursor)
  inspect(free.payload.length(), content="0")
  inspect(cursor.is_empty(), content="true")
}
