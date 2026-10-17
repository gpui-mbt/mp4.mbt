///|
/// `Uint::new(...).unwrap()` の短縮。テスト内で既知値だけを使う。
fn u(value : Int64, bits : Int32, offset : Int32) -> @bytes.Uint {
  @bytes.Uint::new(value.reinterpret_as_uint64(), bits~, offset~).unwrap()
}

///|
/// `VisualSampleEntryFields` の既定値一式（テスト用）。
fn visual_fields() -> @boxes.VisualSampleEntryFields raise @bytes.Mp4Error {
  @boxes.VisualSampleEntryFields::new(
    @boxes.VisualSampleEntryFields::default_data_reference_index(),
    1920U,
    1080U,
    @boxes.VisualSampleEntryFields::default_horizresolution(),
    @boxes.VisualSampleEntryFields::default_vertresolution(),
    @boxes.VisualSampleEntryFields::default_frame_count(),
    @boxes.VisualSampleEntryFields::null_compressorname(),
    @boxes.VisualSampleEntryFields::default_depth(),
  )
}

///|
/// `AudioSampleEntryFields` の既定値一式（テスト用）。
fn audio_fields() -> @boxes.AudioSampleEntryFields {
  @boxes.AudioSampleEntryFields::new(
    @boxes.AudioSampleEntryFields::default_data_reference_index(),
    2U,
    16U,
    @bytes.FixedPointNumber::new(48000, 0U),
  )
}

///|
/// `esds` の最小構成を作る（OTI と DSI payload だけを変える）。
fn esds_box(oti : UInt32, dsi : Bytes?) -> @boxes.EsdsBox {
  @boxes.EsdsBox::new(
    @boxes.EsDescriptor::new(
      1U,
      @boxes.EsDescriptor::lowest_stream_priority(),
      None,
      None,
      None,
      @boxes.DecoderConfigDescriptor::new(
        oti,
        @boxes.DecoderConfigDescriptor::stream_type_audio(),
        u(0, 1, 0),
        u(0, 24, 0),
        0U,
        0U,
        dsi.map(fn(p) { @boxes.DecoderSpecificInfo::new(p) }),
      ),
      @boxes.SlConfigDescriptor::new(),
    ),
  )
}

///|
/// 上流 `hev1.1.6.L93.B0` 例の `hvcC`（space=0, idc=1, compat=0x60000000,
/// constraint[0]=0xB0, tier=L, level=93）。
fn hevc_hvcc() -> @boxes.HvccBox {
  @boxes.HvccBox::new(
    u(0, 2, 0), // general_profile_space
    u(0, 1, 0), // general_tier_flag
    u(1, 5, 0), // general_profile_idc
    0x60000000U, // general_profile_compatibility_flags
    u(0xB00000000000L, 48, 0), // general_constraint_indicator_flags
    93U, // general_level_idc
    u(0, 12, 0), // min_spatial_segmentation_idc
    u(0, 2, 0), // parallelism_type
    u(0, 2, 0), // chroma_format_idc
    u(0, 3, 0), // bit_depth_luma_minus8
    u(0, 3, 0), // bit_depth_chroma_minus8
    0U, // avg_frame_rate
    u(0, 2, 0), // constant_frame_rate
    u(0, 3, 0), // num_temporal_layers
    u(0, 1, 0), // temporal_id_nested
    u(3, 2, 0), // length_size_minus_one
    [],
  )
}

///|
test "avc1 produces RFC 6381 3-byte hex" {
  let entry = @boxes.SampleEntry::Avc1(
    @boxes.Avc1Box::new(
      visual_fields(),
      @boxes.AvccBox::new(
        100U,
        0x00U,
        40U,
        u(3, 2, 0),
        [],
        [],
        None,
        None,
        None,
        [],
      ),
      [],
    ),
  )
  inspect(@codec_string.from_sample_entry(entry), content="avc1.640028")
}

///|
test "hevc produces Annex E form" {
  let hev1 = @boxes.SampleEntry::Hev1(
    @boxes.Hev1Box::new(visual_fields(), hevc_hvcc(), []),
  )
  inspect(@codec_string.from_sample_entry(hev1), content="hev1.1.6.L93.B0")
  let hvc1 = @boxes.SampleEntry::Hvc1(
    @boxes.Hvc1Box::new(visual_fields(), hevc_hvcc(), []),
  )
  inspect(@codec_string.from_sample_entry(hvc1), content="hvc1.1.6.L93.B0")
}

///|
test "av1 produces binding form" {
  let entry = @boxes.SampleEntry::Av01(
    @boxes.Av01Box::new(
      visual_fields(),
      @boxes.Av1cBox::new(
        u(0, 3, 0), // seq_profile
        u(1, 5, 0), // seq_level_idx_0
        u(0, 1, 0), // seq_tier_0
        u(0, 1, 0), // high_bitdepth
        u(0, 1, 0), // twelve_bit
        u(0, 1, 0), // monochrome
        u(0, 1, 0), // chroma_subsampling_x
        u(0, 1, 0), // chroma_subsampling_y
        u(0, 2, 0), // chroma_sample_position
        None, // initial_presentation_delay_minus_one
        b"",
      ),
      [],
    ),
  )
  inspect(@codec_string.from_sample_entry(entry), content="av01.0.01M.08")
}

///|
test "vp8 vp9 produce 4CC.PP.LL.DD" {
  let vpcc = @boxes.VpccBox::new(
    0U,
    31U,
    u(8, 4, 0),
    u(0, 3, 0),
    u(0, 1, 0),
    1U,
    1U,
    1U,
    b"",
  )
  let vp09 = @boxes.SampleEntry::Vp09(
    @boxes.Vp09Box::new(visual_fields(), vpcc, []),
  )
  inspect(@codec_string.from_sample_entry(vp09), content="vp09.00.31.08")
  let vp08 = @boxes.SampleEntry::Vp08(
    @boxes.Vp08Box::new(visual_fields(), vpcc, []),
  )
  inspect(@codec_string.from_sample_entry(vp08), content="vp08.00.31.08")
}

///|
fn mp4a_entry(dsi : Bytes?) -> @boxes.SampleEntry {
  @boxes.SampleEntry::Mp4a(
    @boxes.Mp4aBox::new(audio_fields(), esds_box(0x40U, dsi), []),
  )
}

///|
test "mp4a produces OTI and AOT" {
  inspect(
    @codec_string.from_sample_entry(mp4a_entry(Some(b"\x11\x90"))),
    content="mp4a.40.2",
  )
  // AOT 31 エスケープ: 0xF8 0x00 → ext=0 → AOT 32
  inspect(
    @codec_string.from_sample_entry(mp4a_entry(Some(b"\xF8\x00"))),
    content="mp4a.40.32",
  )
  // 非 0x40 OTI は AOT を付けない
  let entry = @boxes.SampleEntry::Mp4a(
    @boxes.Mp4aBox::new(audio_fields(), esds_box(0x6BU, None), []),
  )
  inspect(@codec_string.from_sample_entry(entry), content="mp4a.6b")
}

///|
test "mp4a errors are invalid_data" {
  // OTI 0x40 で DSI 欠落
  try @codec_string.from_sample_entry(mp4a_entry(None)) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(codec_string_kind_name(kind), content="invalid_data")
      inspect(
        reason,
        content="mp4a object type 0x40 requires DecoderSpecificInfo for codecs string",
      )
    }
  } noraise {
    _ => fail("expected InvalidData")
  }
  // 空 ASC
  try @codec_string.from_sample_entry(mp4a_entry(Some(b""))) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(codec_string_kind_name(kind), content="invalid_data")
      inspect(
        reason,
        content="AudioSpecificConfig is empty; cannot read audioObjectType",
      )
    }
  } noraise {
    _ => fail("expected InvalidData")
  }
  // AOT 31 エスケープの切り詰め（1 バイトのみ）
  try @codec_string.from_sample_entry(mp4a_entry(Some(b"\xF8"))) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(codec_string_kind_name(kind), content="invalid_data")
      inspect(
        reason,
        content="AudioSpecificConfig is truncated at escaped audioObjectType",
      )
    }
  } noraise {
    _ => fail("expected InvalidData")
  }
}

///|
test "opus and flac return bare 4CC" {
  let opus = @boxes.SampleEntry::Opus(
    @boxes.OpusBox::new(audio_fields(), @boxes.DopsBox::new(2U, 312U, 0U, 0), []),
  )
  inspect(@codec_string.from_sample_entry(opus), content="Opus")
  let flac = @boxes.SampleEntry::Flac(
    @boxes.FlacBox::new(
      audio_fields(),
      @boxes.DflaBox::new([
        @boxes.FlacMetadataBlock::new(
          u(1, 1, 0),
          u(0, 7, 0),
          Bytes::from_array(Array::make(34, b'\x00')),
        ),
      ]),
      [],
    ),
  )
  inspect(@codec_string.from_sample_entry(flac), content="fLaC")
}

///|
test "unknown entry is unsupported" {
  let entry = @boxes.SampleEntry::Unknown(
    @boxes.UnknownBox::new(
      @bytes.BoxType::Normal(@bytes.FourCC::from_string("zzzz")),
      @box.BoxSize::U32(8U),
      b"",
    ),
  )
  try @codec_string.from_sample_entry(entry) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(codec_string_kind_name(kind), content="unsupported")
      inspect(
        reason,
        content="codec string is unsupported for unknown sample entry type `zzzz`",
      )
    }
  } noraise {
    _ => fail("expected Unsupported")
  }
}
