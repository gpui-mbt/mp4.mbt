///|
test "minf round trips without a media header" {
  let minf = test_minf()
  let encoded = @bytes.encode_to_bytes(minf)
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.MinfBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded.media_header is None, content="true")
  inspect(decoded == minf, content="true")
  inspect(@box.BaseBox::box_type(decoded).to_string(), content="minf")
  inspect(@box.BaseBox::children(decoded).length(), content="1")
}

///|
test "minf requires dinf" {
  let cursor = @bytes.ReadCursor::new(test_box_bytes(b"minf", b""))
  let result : @boxes.MinfBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Missing mandatory 'dinf' box in 'minf' box")
      None
    }
  } noraise {
    minf => Some(minf)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "minf keeps the first media header and retains later ones as unknown" {
  let dinf = @bytes.encode_to_bytes(@boxes.DinfBox::local_file())
  let payload = test_vmhd_bytes() + test_vmhd_bytes() + test_nmhd_bytes() + dinf
  let bytes = test_box_bytes(b"minf", payload)
  let decoded : @boxes.MinfBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  match decoded.media_header {
    Some(@boxes.MediaHeader::Vmhd(_)) => ()
    _ => fail("最初の vmhd が得られるはず")
  }
  inspect(decoded.unknown_boxes.length(), content="2")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="vmhd")
  inspect(decoded.unknown_boxes[1].box_type.to_string(), content="nmhd")
}

///|
test "minf retains unknown children and keeps stbl until issue 0009" {
  let dinf = @bytes.encode_to_bytes(@boxes.DinfBox::local_file())
  // 型付きの子より前に未知ボックスを置き、children() が型付きを先に返すことを見る。
  let payload = test_unknown_bytes() +
    test_stbl_bytes() +
    test_vmhd_bytes() +
    dinf
  let bytes = test_box_bytes(b"minf", payload)
  let decoded : @boxes.MinfBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  match decoded.media_header {
    Some(@boxes.MediaHeader::Vmhd(_)) => ()
    _ => fail("vmhd が得られるはず")
  }
  inspect(decoded.unknown_boxes.length(), content="2")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="zzzz")
  inspect(decoded.unknown_boxes[1].box_type.to_string(), content="stbl")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="4")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="vmhd")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="dinf")
  inspect(@box.BaseBox::box_type(children[2]).to_string(), content="zzzz")
  inspect(@box.BaseBox::box_type(children[3]).to_string(), content="stbl")
  inspect(children[2].is_unknown_box(), content="true")
  inspect(children[3].is_unknown_box(), content="true")
}
