///|
test "stts round trips run-length entries" {
  let stts = @boxes.SttsBox::new([
    @boxes.SttsEntry::new(2U, 10U),
    @boxes.SttsEntry::new(1U, 20U),
  ])
  let encoded = @bytes.encode_to_bytes(stts)
  // header (8) + full box header (4) + entry_count (4) + 2 entries (16)
  inspect(encoded.length(), content="32")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.SttsBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == stts, content="true")
  inspect(decoded.entries[0].sample_count, content="2")
  inspect(decoded.entries[0].sample_delta, content="10")
  inspect(decoded.entries[1].sample_delta, content="20")
}

///|
test "stts with no entries encodes the empty table" {
  let stts = @boxes.SttsBox::new([])
  let encoded = @bytes.encode_to_bytes(stts)
  inspect(
    encoded == b"\x00\x00\x00\x10stts\x00\x00\x00\x00\x00\x00\x00\x00",
    content="true",
  )
  let decoded : @boxes.SttsBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == stts, content="true")
  inspect(@box.BaseBox::children(decoded).length(), content="0")
}

///|
test "stts from_sample_deltas aggregates equal deltas into runs" {
  let stts = @boxes.SttsBox::from_sample_deltas(
    [10U, 10U, 20U, 20U, 20U, 10U].iter(),
  )
  inspect(stts.entries.length(), content="3")
  inspect(stts.entries[0].sample_count, content="2")
  inspect(stts.entries[0].sample_delta, content="10")
  inspect(stts.entries[1].sample_count, content="3")
  inspect(stts.entries[1].sample_delta, content="20")
  inspect(stts.entries[2].sample_count, content="1")
  inspect(stts.entries[2].sample_delta, content="10")
}

///|
test "stts from_sample_deltas with no deltas is empty" {
  let stts = @boxes.SttsBox::from_sample_deltas(Iter::empty())
  inspect(stts.entries.length(), content="0")
}
