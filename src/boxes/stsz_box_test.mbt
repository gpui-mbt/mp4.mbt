///|
test "stsz fixed round trips the shared sample size" {
  let stsz = @boxes.StszBox::Fixed(
    sample_size=@bytes.NonZeroU32::new(4U).unwrap(),
    sample_count=3U,
  )
  let encoded = @bytes.encode_to_bytes(stsz)
  // header (8) + full box header (4) + sample_size (4) + sample_count (4)
  inspect(encoded.length(), content="20")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.StszBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == stsz, content="true")
}

///|
test "stsz fixed accepts the u32 boundaries" {
  let one = @boxes.StszBox::Fixed(
    sample_size=@bytes.NonZeroU32::new(1U).unwrap(),
    sample_count=0U,
  )
  let decoded : @boxes.StszBox = @bytes.decode_from(
    @bytes.ReadCursor::new(@bytes.encode_to_bytes(one)),
  )
  inspect(decoded == one, content="true")
  let max = @boxes.StszBox::Fixed(
    sample_size=@bytes.NonZeroU32::new(0xFFFFFFFFU).unwrap(),
    sample_count=0xFFFFFFFFU,
  )
  let decoded : @boxes.StszBox = @bytes.decode_from(
    @bytes.ReadCursor::new(@bytes.encode_to_bytes(max)),
  )
  match decoded {
    @boxes.StszBox::Fixed(sample_size~, sample_count~) => {
      inspect(sample_size.get(), content="4294967295")
      inspect(sample_count, content="4294967295")
    }
    @boxes.StszBox::Variable(_) => fail("Fixed が得られるはず")
  }
}

///|
test "stsz variable round trips per-sample sizes" {
  let stsz = @boxes.StszBox::Variable(entry_sizes=[1U, 0U, 4294967295U])
  let encoded = @bytes.encode_to_bytes(stsz)
  // header (8) + full box header (4) + sample_size (4) + entry_count (4) +
  // 3 entries (12)
  inspect(encoded.length(), content="32")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.StszBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == stsz, content="true")
  match decoded {
    @boxes.StszBox::Fixed(..) => fail("Variable が得られるはず")
    @boxes.StszBox::Variable(entry_sizes~) =>
      inspect(entry_sizes.length(), content="3")
  }
}

///|
test "stsz variable with no entries encodes sample_size 0 and count 0" {
  let stsz = @boxes.StszBox::Variable(entry_sizes=[])
  let encoded = @bytes.encode_to_bytes(stsz)
  inspect(
    encoded ==
    b"\x00\x00\x00\x14stsz\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    content="true",
  )
  let decoded : @boxes.StszBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == stsz, content="true")
}

///|
test "stsz decode chooses the variant from the wire sample_size" {
  let fixed_bytes = test_box_bytes(
    b"stsz",
    b"\x00\x00\x00\x00" + b"\x00\x00\x00\x04" + b"\x00\x00\x00\x02",
  )
  let decoded : @boxes.StszBox = @bytes.decode_from(
    @bytes.ReadCursor::new(fixed_bytes),
  )
  match decoded {
    @boxes.StszBox::Fixed(sample_size~, sample_count~) => {
      inspect(sample_size.get(), content="4")
      inspect(sample_count, content="2")
    }
    @boxes.StszBox::Variable(_) => fail("Fixed が得られるはず")
  }
  let variable_bytes = test_box_bytes(
    b"stsz",
    b"\x00\x00\x00\x00" +
    b"\x00\x00\x00\x00" +
    b"\x00\x00\x00\x02" +
    b"\x00\x00\x00\x07" +
    b"\x00\x00\x00\x09",
  )
  let decoded : @boxes.StszBox = @bytes.decode_from(
    @bytes.ReadCursor::new(variable_bytes),
  )
  match decoded {
    @boxes.StszBox::Fixed(..) => fail("Variable が得られるはず")
    @boxes.StszBox::Variable(entry_sizes~) => {
      inspect(entry_sizes.length(), content="2")
      inspect(entry_sizes[0], content="7")
      inspect(entry_sizes[1], content="9")
    }
  }
}
