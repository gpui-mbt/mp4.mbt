///|
fn h264_test_sps() -> Bytes {
  b"\x67\x64\x00\x1e\xac\xd9\x40\xa0\x3d\xb0\x11\x00\x00\x03\x00\x01\x00\x00\x03\x00\x32\x0f\x16\x2d\x96\x01\x00\x06\x68\xeb\xe3\xcb\x22\xc0\xfd\xf8\xf8"
}

///|
fn h264_test_pps() -> Bytes {
  b"\x68\xeb\xe3\xcb\x22\xc0"
}

///|
test "h264 parses annex b nal units" {
  let input = b"\x00\x00\x00\x01\x67\x64\x00\x1e\x00\x00\x01\x68\xeb\xe3\xcb\x22\xc0"
  let nals = @bitstream.parse_annexb_nal_units(input)
  inspect(nals.length(), content="2")
  inspect(
    nals[0].nal_unit_type is @bitstream.H264NalUnitType::Sps,
    content="true",
  )
  inspect(
    nals[1].nal_unit_type is @bitstream.H264NalUnitType::Pps,
    content="true",
  )
}

///|
test "h264 parses length prefixed nal units and converts" {
  let annexb = b"\x00\x00\x00\x01\x67\x64\x00\x1e\x00\x00\x00\x01\x68\xeb\xe3\xcb\x22\xc0"
  let length_prefixed = @bitstream.annexb_to_length_prefixed(
    annexb,
    @bitstream.LengthSize::Four,
  )
  let nals = @bitstream.parse_length_prefixed_nal_units(
    length_prefixed,
    @bitstream.LengthSize::Four,
  )
  inspect(nals.length(), content="2")
  let roundtrip = @bitstream.length_prefixed_to_annexb(
    length_prefixed,
    @bitstream.LengthSize::Four,
  )
  inspect(roundtrip.length() > 0, content="true")
}

///|
test "h264 parses sps dimensions and profile" {
  let sps = @bitstream.parse_sps(h264_test_sps())
  inspect(sps.profile_level_id.profile_idc, content="100")
  inspect(sps.profile_level_id.level_idc, content="30")
  inspect(sps.width, content="640")
  inspect(sps.height, content="480")
}

///|
test "h264 builds avc1 from sps and pps" {
  let config = @bitstream.H264SampleEntryConfig::new(
    @bitstream.LengthSize::Four,
  )
  let box = @bitstream.build_avc1_box(
    [h264_test_sps()],
    [h264_test_pps()],
    config,
  )
  let bytes = @bytes.encode_to_bytes(box)
  inspect(bytes.length() > 0, content="true")
  let decoded : @boxes.Avc1Box = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.visual.width, content="640")
  inspect(decoded.visual.height, content="480")
  inspect(decoded.avcc_box.sps_list.length(), content="1")
  inspect(decoded.avcc_box.pps_list.length(), content="1")
}

///|
test "h264 profile level id hex round trips" {
  let id = @bitstream.H264ProfileLevelId::from_hex("64001e")
  inspect(id.profile_idc, content="100")
  inspect(id.level_idc, content="30")
  inspect(id.to_hex(), content="64001e")
}
