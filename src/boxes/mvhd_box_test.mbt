///|
test "mvhd version 0 round trips with 32-bit fields" {
  let mvhd = @boxes.MvhdBox::new(
    @bytes.Mp4FileTime::from_secs(1UL),
    @bytes.Mp4FileTime::from_secs(2UL),
    @bytes.NonZeroU32::new(1000U).unwrap(),
    2000UL,
    @boxes.MvhdBox::default_rate(),
    @boxes.MvhdBox::default_volume(),
    @boxes.MvhdBox::default_matrix(),
    1U,
  )
  let encoded = @bytes.encode_to_bytes(mvhd)
  inspect(encoded[8].to_uint(), content="0")
  inspect(encoded.length(), content="108")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.MvhdBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == mvhd, content="true")
  inspect(decoded.creation_time.as_secs(), content="1")
  inspect(decoded.modification_time.as_secs(), content="2")
  inspect(decoded.timescale.get(), content="1000")
  inspect(decoded.duration, content="2000")
  inspect(decoded.rate == @boxes.MvhdBox::default_rate(), content="true")
  inspect(decoded.volume == @boxes.MvhdBox::default_volume(), content="true")
  inspect(decoded.matrix.length(), content="9")
  inspect(decoded.matrix[0], content="65536")
  inspect(decoded.next_track_id, content="1")
}

///|
test "mvhd uses version 1 when a 64-bit value exceeds u32 max" {
  let mvhd = @boxes.MvhdBox::new(
    @bytes.Mp4FileTime::from_secs(4294967295UL),
    @bytes.Mp4FileTime::from_secs(4294967296UL),
    @bytes.NonZeroU32::new(1000U).unwrap(),
    4294967297UL,
    @boxes.MvhdBox::default_rate(),
    @boxes.MvhdBox::default_volume(),
    @boxes.MvhdBox::default_matrix(),
    1U,
  )
  let encoded = @bytes.encode_to_bytes(mvhd)
  inspect(encoded[8].to_uint(), content="1")
  inspect(encoded.length(), content="120")
  let decoded : @boxes.MvhdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded.creation_time.as_secs(), content="4294967295")
  inspect(decoded.modification_time.as_secs(), content="4294967296")
  inspect(decoded.duration, content="4294967297")
  inspect(decoded == mvhd, content="true")
}

///|
test "mvhd keeps version 0 at exactly u32 max" {
  let mvhd = @boxes.MvhdBox::new(
    @bytes.Mp4FileTime::from_secs(4294967295UL),
    @bytes.Mp4FileTime::from_secs(4294967295UL),
    @bytes.NonZeroU32::new(1000U).unwrap(),
    4294967295UL,
    @boxes.MvhdBox::default_rate(),
    @boxes.MvhdBox::default_volume(),
    @boxes.MvhdBox::default_matrix(),
    1U,
  )
  let encoded = @bytes.encode_to_bytes(mvhd)
  inspect(encoded[8].to_uint(), content="0")
  inspect(encoded.length(), content="108")
}

///|
test "mvhd decode rejects a zero timescale" {
  let encoded = @bytes.encode_to_bytes(test_mvhd())
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
  let result : @boxes.MvhdBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Expected a non-zero integer, but got 0")
      None
    }
  } noraise {
    mvhd => Some(mvhd)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
