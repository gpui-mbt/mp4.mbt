///|
fn h265_test_vps() -> Bytes {
  b"\x40\x01\x00"
}

///|
fn h265_test_sps() -> Bytes {
  b"\x42\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
}

///|
fn h265_test_pps() -> Bytes {
  b"\x44\x01\x00"
}

///|
test "h265 parses annex b nal units" {
  let input = b"\x00\x00\x00\x01\x40\x01\x00\x00\x00\x01\x42\x01\x00\x00"
  let nals = @bitstream.parse_annexb_nal_units_h265(input)
  inspect(nals.length(), content="2")
  inspect(
    nals[0].nal_unit_type is @bitstream.H265NalUnitType::Vps,
    content="true",
  )
  inspect(
    nals[1].nal_unit_type is @bitstream.H265NalUnitType::Sps,
    content="true",
  )
}

///|
test "h265 builds hev1 and hvc1 boxes" {
  let config = @bitstream.H265SampleEntryConfig::new(
    @bitstream.LengthSize::Four,
    1920U,
    1080U,
  )
  let box = @bitstream.build_hev1_box(
    [h265_test_vps()],
    [h265_test_sps()],
    [h265_test_pps()],
    config,
  )
  let bytes = @bytes.encode_to_bytes(box)
  let decoded : @boxes.Hev1Box = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.visual.width, content="1920")
  inspect(decoded.visual.height, content="1080")
  inspect(decoded.hvcc_box.nalu_arrays.length(), content="3")

  let hvc1 = @bitstream.build_hvc1_box(
    [h265_test_vps()],
    [h265_test_sps()],
    [h265_test_pps()],
    config,
  )
  inspect(@bytes.encode_to_bytes(hvc1).length() > 0, content="true")
}
