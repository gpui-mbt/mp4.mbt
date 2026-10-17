///|
fn subtitle_utf8(value : String) -> @bytes.Utf8String {
  @bytes.Utf8String::new(value).unwrap()
}

///|
test "stpp round trips metadata" {
  let box = @boxes.StppBox::new(
    @bytes.NonZeroU16::one(),
    subtitle_utf8("http://www.w3.org/ns/ttml"),
    subtitle_utf8(""),
    subtitle_utf8(""),
    [],
  )
  let bytes = @bytes.encode_to_bytes(box)
  let decoded : @boxes.StppBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.namespace_uri.get(), content="http://www.w3.org/ns/ttml")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
test "wvtt round trips vttC" {
  let box = @boxes.WvttBox::new(
    @bytes.NonZeroU16::one(),
    @boxes.VttCBox::new("WEBVTT"),
    [],
  )
  let bytes = @bytes.encode_to_bytes(box)
  let decoded : @boxes.WvttBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.vttc_box.config, content="WEBVTT")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
fn subtitle_style() -> @boxes.StyleRecord {
  @boxes.StyleRecord::new(0U, 0U, 1U, 0U, 12U, b"\x00\x00\x00\xFF")
}

///|
test "tx3g round trips fields and ftab" {
  let box = @boxes.Tx3gBox::new(
    @bytes.NonZeroU16::one(),
    0U,
    0,
    0,
    b"\x00\x00\x00\x00",
    @boxes.BoxRecord::new(0, 0, 0, 0),
    subtitle_style(),
    @boxes.FtabBox::new([@boxes.FontRecord::new(1U, b"Sans")]),
    [],
  )
  let bytes = @bytes.encode_to_bytes(box)
  let decoded : @boxes.Tx3gBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.default_style.font_size, content="12")
  inspect(decoded.ftab_box.entries.length(), content="1")
  inspect(decoded.ftab_box.entries[0].font_name == b"Sans", content="true")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
test "stsd decodes subtitle sample entry variants" {
  let entry : @boxes.SampleEntry = @boxes.SampleEntry::Wvtt(
    @boxes.WvttBox::new(
      @bytes.NonZeroU16::one(),
      @boxes.VttCBox::new("WEBVTT"),
      [],
    ),
  )
  let stsd = @boxes.StsdBox::new([entry])
  let decoded : @boxes.StsdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(@bytes.encode_to_bytes(stsd)),
  )
  inspect(decoded.entries.length(), content="1")
  inspect(decoded.entries[0] is @boxes.SampleEntry::Wvtt(_), content="true")
}
