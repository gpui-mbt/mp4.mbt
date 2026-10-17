///|
test "sdtp sample flags pack fields into the top-down bit layout" {
  let flags = @boxes.SdtpSampleFlags::from_fields(
    b'\x01', b'\x02', b'\x03', b'\x00',
  )
  inspect(flags.get().to_uint(), content="108")
  inspect(flags.is_leading().to_uint(), content="1")
  inspect(flags.sample_depends_on().to_uint(), content="2")
  inspect(flags.sample_is_depended_on().to_uint(), content="3")
  inspect(flags.sample_has_redundancy().to_uint(), content="0")
}

///|
test "sdtp sample flags mask each field to two bits" {
  let flags = @boxes.SdtpSampleFlags::from_fields(
    b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  )
  inspect(flags.get().to_uint(), content="255")
  inspect(flags.is_leading().to_uint(), content="3")
  inspect(flags.sample_depends_on().to_uint(), content="3")
  inspect(flags.sample_is_depended_on().to_uint(), content="3")
  inspect(flags.sample_has_redundancy().to_uint(), content="3")
}

///|
test "sdtp round trips entries" {
  let sdtp = @boxes.SdtpBox::new([
    @boxes.SdtpSampleFlags::from_fields(b'\x00', b'\x01', b'\x00', b'\x00'),
    @boxes.SdtpSampleFlags::from_fields(b'\x00', b'\x02', b'\x01', b'\x00'),
  ])
  let encoded = @bytes.encode_to_bytes(sdtp)
  // header (8) + full box header (4) + 2 entries (2)
  inspect(encoded.length(), content="14")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.SdtpBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == sdtp, content="true")
}

///|
test "sdtp with no entries round trips" {
  let sdtp = @boxes.SdtpBox::new([])
  let encoded = @bytes.encode_to_bytes(sdtp)
  inspect(encoded == b"\x00\x00\x00\x0Csdtp\x00\x00\x00\x00", content="true")
  let decoded : @boxes.SdtpBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == sdtp, content="true")
}

///|
test "sdtp decode reads entries to the end of the payload" {
  // entry_count は wire 上に無く、FullBox ヘッダーの後ろがすべて 1 サンプル 1 バイト。
  let bytes = test_box_bytes(b"sdtp", b"\x00\x00\x00\x00" + b"\x00\x01\x02")
  let decoded : @boxes.SdtpBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.entries.length(), content="3")
  inspect(decoded.entries[2].get().to_uint(), content="2")
}

///|
test "sdtp decode rejects a non-zero version" {
  let bytes = test_box_bytes(b"sdtp", b"\x01\x00\x00\x00" + b"\x00")
  let cursor = @bytes.ReadCursor::new(bytes)
  let result : @boxes.SdtpBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Invalid sdtp box version: 1")
      None
    }
  } noraise {
    sdtp => Some(sdtp)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
