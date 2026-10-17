///|
test "mdhd version 0 round trips with the packed language" {
  let mdhd = @boxes.MdhdBox::new(
    @bytes.Mp4FileTime::from_secs(1UL),
    @bytes.Mp4FileTime::from_secs(2UL),
    @bytes.NonZeroU32::new(48000U).unwrap(),
    96000UL,
    @bytes.LanguageCode::from_ascii("jpn").unwrap(),
  )
  let encoded = @bytes.encode_to_bytes(mdhd)
  inspect(encoded[8].to_uint(), content="0")
  inspect(encoded.length(), content="32")
  // 言語は unsigned int(5)[3] として payload の language フィールドに
  // パックされる（"jpn" → 0x2A0E）。
  inspect(encoded[28].to_uint(), content="42")
  inspect(encoded[29].to_uint(), content="14")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.MdhdBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == mdhd, content="true")
  inspect(decoded.language.to_string(), content="jpn")
  inspect(decoded.language.to_packed(), content="10766")
  inspect(decoded.timescale.get(), content="48000")
  inspect(decoded.duration, content="96000")
}

///|
test "mdhd uses version 1 above u32 max and round trips" {
  let mdhd = @boxes.MdhdBox::new(
    @bytes.Mp4FileTime::from_secs(4294967296UL),
    @bytes.Mp4FileTime::from_secs(4294967297UL),
    @bytes.NonZeroU32::new(48000U).unwrap(),
    4294967298UL,
    @bytes.LanguageCode::undefined(),
  )
  let encoded = @bytes.encode_to_bytes(mdhd)
  inspect(encoded[8].to_uint(), content="1")
  inspect(encoded.length(), content="44")
  let decoded : @boxes.MdhdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded.creation_time.as_secs(), content="4294967296")
  inspect(decoded.modification_time.as_secs(), content="4294967297")
  inspect(decoded.duration, content="4294967298")
  inspect(decoded == mdhd, content="true")
}

///|
test "mdhd decode rejects a zero timescale" {
  let encoded = @bytes.encode_to_bytes(test_mdhd())
  let patched = FixedArray::make(encoded.length(), b'\x00')
  for i in 0..<encoded.length() {
    patched[i] = encoded[i]
  }
  // header（0..8）+ version/flags（8..12）+ creation（12..16）+
  // modification（16..20）の後が timescale（20..24）。
  patched[20] = b'\x00'
  patched[21] = b'\x00'
  patched[22] = b'\x00'
  patched[23] = b'\x00'
  let cursor = @bytes.ReadCursor::new(Bytes::from_array(patched))
  let result : @boxes.MdhdBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Expected a non-zero integer, but got 0")
      None
    }
  } noraise {
    mdhd => Some(mdhd)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
