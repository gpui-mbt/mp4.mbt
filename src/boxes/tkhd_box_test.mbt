///|
test "tkhd flags and 32-bit fields round trip" {
  let tkhd = @boxes.TkhdBox::new(
    true,
    false,
    true,
    true,
    @bytes.Mp4FileTime::from_secs(3UL),
    @bytes.Mp4FileTime::from_secs(4UL),
    7U,
    1000UL,
    Int16::from_int(-1),
    Int16::from_int(-2),
    @boxes.TkhdBox::default_audio_volume(),
    @boxes.TkhdBox::default_matrix(),
    @bytes.FixedPointNumber::new(1920, 0),
    @bytes.FixedPointNumber::new(1080, 0),
  )
  let encoded = @bytes.encode_to_bytes(tkhd)
  inspect(encoded[8].to_uint(), content="0")
  inspect(encoded.length(), content="92")
  let decoded : @boxes.TkhdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded == tkhd, content="true")
  inspect(decoded.flag_track_enabled, content="true")
  inspect(decoded.flag_track_in_movie, content="false")
  inspect(decoded.flag_track_in_preview, content="true")
  inspect(decoded.flag_track_size_is_aspect_ratio, content="true")
  inspect(decoded.track_id, content="7")
  inspect(decoded.duration, content="1000")
  inspect(decoded.layer, content="-1")
  inspect(decoded.alternate_group, content="-2")
  inspect(
    decoded.volume == @boxes.TkhdBox::default_audio_volume(),
    content="true",
  )
  inspect(decoded.width.integer(), content="1920")
  inspect(decoded.height.integer(), content="1080")
}

///|
test "tkhd uses version 1 above u32 max and round trips" {
  let tkhd = @boxes.TkhdBox::new(
    true,
    true,
    true,
    true,
    @bytes.Mp4FileTime::from_secs(0UL),
    @bytes.Mp4FileTime::from_secs(0UL),
    1U,
    4294967296UL,
    @boxes.TkhdBox::default_layer(),
    @boxes.TkhdBox::default_alternate_group(),
    @boxes.TkhdBox::default_video_volume(),
    @boxes.TkhdBox::default_matrix(),
    @bytes.FixedPointNumber::new(1920, 0),
    @bytes.FixedPointNumber::new(1080, 0),
  )
  let encoded = @bytes.encode_to_bytes(tkhd)
  inspect(encoded[8].to_uint(), content="1")
  inspect(encoded.length(), content="104")
  let decoded : @boxes.TkhdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded.duration, content="4294967296")
  inspect(decoded == tkhd, content="true")
}

///|
test "tkhd keeps version 0 at exactly u32 max" {
  let tkhd = @boxes.TkhdBox::new(
    false,
    false,
    false,
    false,
    @bytes.Mp4FileTime::from_secs(4294967295UL),
    @bytes.Mp4FileTime::from_secs(0UL),
    1U,
    4294967295UL,
    @boxes.TkhdBox::default_layer(),
    @boxes.TkhdBox::default_alternate_group(),
    @boxes.TkhdBox::default_video_volume(),
    @boxes.TkhdBox::default_matrix(),
    @bytes.FixedPointNumber::new(0, 0),
    @bytes.FixedPointNumber::new(0, 0),
  )
  let encoded = @bytes.encode_to_bytes(tkhd)
  inspect(encoded[8].to_uint(), content="0")
  let decoded : @boxes.TkhdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded.flag_track_enabled, content="false")
  inspect(decoded.flag_track_in_movie, content="false")
  inspect(decoded.flag_track_in_preview, content="false")
  inspect(decoded.flag_track_size_is_aspect_ratio, content="false")
  inspect(decoded == tkhd, content="true")
}
