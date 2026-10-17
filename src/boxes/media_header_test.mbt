///|
test "media header dispatches smhd with an unsigned 8.8 balance" {
  let header : @boxes.MediaHeader = @bytes.decode_from(
    @bytes.ReadCursor::new(
      b"\x00\x00\x00\x10smhd\x00\x00\x00\x00\x01\x80\x00\x00",
    ),
  )
  match header {
    @boxes.MediaHeader::Smhd(box) => {
      inspect(box.balance.integer(), content="1")
      inspect(box.balance.fraction(), content="128")
    }
    _ => fail("smhd が得られるはず")
  }
  inspect(@box.BaseBox::box_type(header).to_string(), content="smhd")
  inspect(
    @bytes.encode_to_bytes(header) ==
    b"\x00\x00\x00\x10smhd\x00\x00\x00\x00\x01\x80\x00\x00",
    content="true",
  )
}

///|
test "media header dispatches vmhd and canonicalizes the flags" {
  let header : @boxes.MediaHeader = @bytes.decode_from(
    @bytes.ReadCursor::new(test_vmhd_bytes()),
  )
  match header {
    @boxes.MediaHeader::Vmhd(box) => {
      inspect(box.graphicsmode, content="100")
      inspect(box.opcolor.length(), content="3")
      inspect(box.opcolor[0], content="255")
      inspect(box.opcolor[1], content="128")
      inspect(box.opcolor[2], content="64")
    }
    _ => fail("vmhd が得られるはず")
  }
  inspect(@bytes.encode_to_bytes(header) == test_vmhd_bytes(), content="true")
}

///|
test "vmhd decode accepts flags 0 and re-encodes with flags 1" {
  let zero_flags = b"\x00\x00\x00\x14vmhd\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  let box : @boxes.VmhdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(zero_flags),
  )
  inspect(box.graphicsmode, content="0")
  inspect(
    @bytes.encode_to_bytes(box) ==
    b"\x00\x00\x00\x14vmhd\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00",
    content="true",
  )
}

///|
test "media header dispatches sthd and nmhd" {
  let sthd : @boxes.MediaHeader = @bytes.decode_from(
    @bytes.ReadCursor::new(b"\x00\x00\x00\x0Csthd\x00\x00\x00\x00"),
  )
  match sthd {
    @boxes.MediaHeader::Sthd(box) =>
      inspect(box == @boxes.SthdBox::new(), content="true")
    _ => fail("sthd が得られるはず")
  }
  inspect(@box.BaseBox::box_type(sthd).to_string(), content="sthd")
  let nmhd : @boxes.MediaHeader = @bytes.decode_from(
    @bytes.ReadCursor::new(test_nmhd_bytes()),
  )
  match nmhd {
    @boxes.MediaHeader::Nmhd(box) =>
      inspect(box == @boxes.NmhdBox::new(), content="true")
    _ => fail("nmhd が得られるはず")
  }
  inspect(@box.BaseBox::box_type(nmhd).to_string(), content="nmhd")
  inspect(@bytes.encode_to_bytes(sthd).length(), content="12")
  inspect(@bytes.encode_to_bytes(nmhd) == test_nmhd_bytes(), content="true")
}

///|
test "media header rejects an unexpected child type" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x08zzzz")
  let result : @boxes.MediaHeader? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="unexpected box type for MediaHeader: zzzz")
      None
    }
  } noraise {
    header => Some(header)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
