///|
test "av1 decodes leb128 and obus" {
  let (value, consumed) = @bitstream.decode_leb128(b"\xac\x02")
  inspect(value, content="300")
  inspect(consumed, content="2")
  // Sequence Header OBU (type 1, has_size_field=1), size 2
  let obu = b"\x0A\x02\x18\x00"
  let obus = @bitstream.parse_obus(obu, @bitstream.Av1ObuParseContext::Config)
  inspect(obus.length(), content="1")
  inspect(
    obus[0].obu_type is @bitstream.Av1ObuType::SequenceHeader,
    content="true",
  )
  inspect(obus[0].payload.length(), content="2")
}

///|
test "av1 builds an av01 sample entry" {
  let obu = b"\x0A\x02\x18\x00"
  let box = @bitstream.build_av01_box_from_config_obus(obu, 1920U, 1080U)
  let bytes = @bytes.encode_to_bytes(box)
  let decoded : @boxes.Av01Box = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.visual.width, content="1920")
  inspect(decoded.visual.height, content="1080")
}

///|
test "vp8 parses a keyframe tag and builds vp08" {
  // keyframe tag: frame_type=0, version=0, show_frame=1, size=10
  let tag : UInt32 = (10U << 5) | (1U << 4)
  let writer = @bytes.WriteCursor::new()
  writer.write_u8(tag & 0xFFU)
  writer.write_u8((tag >> 8) & 0xFFU)
  writer.write_u8((tag >> 16) & 0xFFU)
  let header = @bitstream.parse_vp8_frame_header(writer.to_bytes())
  inspect(header.keyframe, content="true")
  inspect(header.first_partition_size, content="10")
  let config = @bitstream.Vp8SampleEntryConfig::new(640U, 480U)
  let box = @bitstream.build_vp08_box(config)
  inspect(@bytes.encode_to_bytes(box).length() > 0, content="true")
}

///|
test "vp9 parses a keyframe header and builds vp09" {
  // frame_marker=2, profile=0, show_existing=0, frame_type=0, show_frame=1,
  // error_resilient=0
  let input = b"\x82"
  let header = @bitstream.parse_vp9_frame_header(input)
  inspect(header.keyframe, content="true")
  inspect(header.profile, content="0")
  inspect(header.bit_depth, content="8")
  let config = @bitstream.Vp9SampleEntryConfig::new(640U, 480U)
  let box = @bitstream.build_vp09_box(header, config)
  inspect(@bytes.encode_to_bytes(box).length() > 0, content="true")
}
