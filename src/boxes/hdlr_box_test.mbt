///|
test "hdlr handler type helpers build the upstream fourcc values" {
  inspect(@boxes.HdlrBox::handler_type_vide().to_string(), content="vide")
  inspect(@boxes.HdlrBox::handler_type_soun().to_string(), content="soun")
  inspect(@boxes.HdlrBox::handler_type_subt().to_string(), content="subt")
  inspect(@boxes.HdlrBox::handler_type_text().to_string(), content="text")
}

///|
test "hdlr maps handler types to track kinds" {
  let vide = @boxes.HdlrBox::new(@boxes.HdlrBox::handler_type_vide(), b"")
  inspect(vide.track_kind() is Some(@bytes.TrackKind::Video), content="true")
  let soun = @boxes.HdlrBox::new(@boxes.HdlrBox::handler_type_soun(), b"")
  inspect(soun.track_kind() is Some(@bytes.TrackKind::Audio), content="true")
  let subt = @boxes.HdlrBox::new(@boxes.HdlrBox::handler_type_subt(), b"")
  inspect(subt.track_kind() is Some(@bytes.TrackKind::Subtitle), content="true")
  let text = @boxes.HdlrBox::new(@boxes.HdlrBox::handler_type_text(), b"")
  inspect(text.track_kind() is Some(@bytes.TrackKind::Subtitle), content="true")
  let unknown = @boxes.HdlrBox::new(@bytes.FourCC::from_string("zzzz"), b"")
  inspect(unknown.track_kind() is None, content="true")
}

///|
test "hdlr keeps the raw name bytes including an embedded NUL" {
  let name = b"Vi\x00deo\xFF\xFE"
  let payload = b"\x00\x00\x00\x00" +
    b"\x00\x00\x00\x00" +
    b"vide" +
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
    name
  let bytes = test_box_bytes(b"hdlr", payload)
  let cursor = @bytes.ReadCursor::new(bytes)
  let decoded : @boxes.HdlrBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded.handler_type.to_string(), content="vide")
  inspect(decoded.name == name, content="true")
  // version / flags / pre_defined / reserved が 0 の入力なので canonical に戻る。
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
test "hdlr decode drops version flags and pre_defined on re-encode" {
  let payload = b"\x01\x00\x00\x07" +
    b"\xAB\xCD\xEF\x01" +
    b"soun" +
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
    b"\x41\x00"
  let decoded : @boxes.HdlrBox = @bytes.decode_from(
    @bytes.ReadCursor::new(test_box_bytes(b"hdlr", payload)),
  )
  inspect(decoded.handler_type.to_string(), content="soun")
  inspect(decoded.name == b"\x41\x00", content="true")
  let canonical_payload = b"\x00\x00\x00\x00" +
    b"\x00\x00\x00\x00" +
    b"soun" +
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
    b"\x41\x00"
  inspect(
    @bytes.encode_to_bytes(decoded) ==
    test_box_bytes(b"hdlr", canonical_payload),
    content="true",
  )
}

///|
test "hdlr with an empty name round trips" {
  let hdlr = @boxes.HdlrBox::new(@boxes.HdlrBox::handler_type_soun(), b"")
  let encoded = @bytes.encode_to_bytes(hdlr)
  // header 8 + version/flags 4 + pre_defined 4 + handler_type 4 + reserved 12
  inspect(encoded.length(), content="32")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.HdlrBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == hdlr, content="true")
  inspect(decoded.name.length(), content="0")
}
