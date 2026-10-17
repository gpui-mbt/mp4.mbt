///|
test "stsd with no entries encodes an empty table" {
  let stsd = @boxes.StsdBox::new([])
  let encoded = @bytes.encode_to_bytes(stsd)
  inspect(
    encoded == b"\x00\x00\x00\x10stsd\x00\x00\x00\x00\x00\x00\x00\x00",
    content="true",
  )
  let decoded : @boxes.StsdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == stsd, content="true")
  inspect(@box.BaseBox::children(decoded).length(), content="0")
}

///|
test "stsd with a single entry round trips" {
  let stsd = @boxes.StsdBox::new([test_sample_entry()])
  let encoded = @bytes.encode_to_bytes(stsd)
  // header (8) + full box header (4) + entry_count (4) + entry (8)
  inspect(encoded.length(), content="24")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.StsdBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == stsd, content="true")
  inspect(decoded.entries.length(), content="1")
  inspect(
    @box.BaseBox::box_type(decoded.entries[0]).to_string(),
    content="test",
  )
  inspect(decoded.entries[0].is_unknown_box(), content="true")
}

///|
test "stsd with multiple entries writes the entry count from the length" {
  let entries = [test_sample_entry(), test_sample_entry()]
  let stsd = @boxes.StsdBox::new(entries)
  let encoded = @bytes.encode_to_bytes(stsd)
  // entry_count は length から書かれる。
  inspect(encoded[12].to_uint(), content="0")
  inspect(encoded[13].to_uint(), content="0")
  inspect(encoded[14].to_uint(), content="0")
  inspect(encoded[15].to_uint(), content="2")
  let decoded : @boxes.StsdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded.entries.length(), content="2")
  inspect(@box.BaseBox::children(decoded).length(), content="2")
}

///|
test "stsd decode reads exactly entry_count entries" {
  // entry_count は 1 だが 2 エントリー分のバイト列が続く。余りは読まない。
  let bytes = test_box_bytes(
    b"stsd",
    b"\x00\x00\x00\x00" +
    b"\x00\x00\x00\x01" +
    test_sample_entry_bytes() +
    test_sample_entry_bytes(),
  )
  let cursor = @bytes.ReadCursor::new(bytes)
  let decoded : @boxes.StsdBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded.entries.length(), content="1")
}

///|
test "stsd decode ignores the full box version and flags" {
  let bytes = test_box_bytes(b"stsd", b"\x01\x12\x34\x56" + b"\x00\x00\x00\x00")
  let decoded : @boxes.StsdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.entries.length(), content="0")
  // 再エンコード時は version 0 / flags 0 に正規化される。
  inspect(
    @bytes.encode_to_bytes(decoded) ==
    b"\x00\x00\x00\x10stsd\x00\x00\x00\x00\x00\x00\x00\x00",
    content="true",
  )
}
