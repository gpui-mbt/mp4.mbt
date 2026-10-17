///|
/// Rust oracle の `sample-entries-cases` が返すサンプルエントリー 1 件分
/// （生成データ用）。
///
/// 生成元は `src/boxes/sample_entry_oracle_cases_test.mbt`。
struct OracleSampleEntryCase {
  name : String
  input : Bytes
  ok : Bool
  snapshot : Array[String]
  error_kind : String
  reason : String
  encoded : Bytes
  encode_error_kind : String
  encode_error_reason : String
}

///|
/// Rust oracle が fixture の `stsd` から抽出し、上流で再エンコードした
/// サンプルエントリー 1 件分（生成データ用）。
///
/// 生成元は `src/boxes/sample_entry_oracle_fixtures_test.mbt`。
struct OracleSampleEntryFixture {
  name : String
  track_index : Int32
  entry_index : Int32
  input : Bytes
  snapshot : Array[String]
}

///|
/// 16 進 1 桁（小文字）を返す。
fn sample_entry_hex_digit(n : UInt64) -> Char {
  (if n < 10UL { n + 48UL } else { n + 87UL }).to_byte().to_char()
}

///|
/// `value` を `width` 桁の 0 埋め小文字 16 進にする（Rust の `{:0Nx}` と同じ）。
fn sample_entry_hex_padded(value : UInt64, width : Int32) -> String {
  let sb = StringBuilder()
  for i = width - 1; i >= 0; i = i - 1 {
    sb.write_char(sample_entry_hex_digit((value >> (i * 4)) & 0xFUL))
  }
  sb.to_string()
}

///|
/// `Bytes` を小文字 16 進にする（Rust oracle の `hex` と同じ）。
fn sample_entry_hex(bytes : Bytes) -> String {
  let sb = StringBuilder()
  for i in 0..<bytes.length() {
    let b = bytes[i].to_uint().to_uint64()
    sb.write_char(sample_entry_hex_digit(b >> 4))
    sb.write_char(sample_entry_hex_digit(b & 0xFUL))
  }
  sb.to_string()
}

///|
/// `Bytes` を Rust の `{:?}`（`[1, 2, 3]` 形式）と同じ十進表記にする。
fn sample_entry_rust_debug_bytes(bytes : Bytes) -> String {
  let parts : Array[String] = []
  for i in 0..<bytes.length() {
    parts.push(bytes[i].to_uint().to_string())
  }
  "[\{parts.join(", ")}]"
}

///|
/// 上流 `BoxType` の `Display` と同じ文字列にする。
///
/// 通常種別は 4 バイトがすべて ASCII（`< 0x80`）ならその文字列、それ以外は
/// Rust デバッグ表記 `[d, d, d, d]`。uuid は 16 バイトのデバッグ表記。
fn sample_entry_box_type_str(box_type : @bytes.BoxType) -> String {
  match box_type {
    Normal(fourcc) => {
      let bytes = fourcc.as_bytes()
      let mut ascii = true
      for i in 0..<4 {
        if bytes[i] >= 0x80 {
          ascii = false
        }
      }
      if ascii {
        fourcc.to_string()
      } else {
        sample_entry_rust_debug_bytes(bytes)
      }
    }
    Uuid(uuid) => sample_entry_rust_debug_bytes(uuid.as_bytes())
  }
}

///|
/// `String` を oracle の `json_string_to` と同じ JSON 文字列リテラルにする。
fn sample_entry_json_string(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      c =>
        if c.to_int() < 0x20 {
          let esc = sample_entry_hex_padded(c.to_int().to_uint64(), 4)
          sb.write_string("\\u\{esc}")
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// `Option[UInt64]` 系を `key=value|none` 行にする。
fn sample_entry_opt_num(name : String, value : UInt64?) -> String {
  match value {
    Some(v) => "\{name}=\{v}"
    None => "\{name}=none"
  }
}

///|
/// `u16.u16` 固定小数点を `{:04x}{:04x}` にする。
fn sample_entry_fixed_16_16(value : @bytes.FixedPointNumber) -> String {
  let integer = value.integer().reinterpret_as_uint().to_uint64() & 0xFFFFUL
  let fraction = value.fraction().to_uint64() & 0xFFFFUL
  "\{sample_entry_hex_padded(integer, 4)}\{sample_entry_hex_padded(fraction, 4)}"
}

///|
fn sample_entry_visual_lines(
  lines : Array[String],
  prefix : String,
  v : @boxes.VisualSampleEntryFields,
) -> Unit {
  lines.push("\{prefix}.data_reference_index=\{v.data_reference_index.get()}")
  lines.push("\{prefix}.width=\{v.width}")
  lines.push("\{prefix}.height=\{v.height}")
  lines.push(
    "\{prefix}.horizresolution=\{sample_entry_fixed_16_16(v.horizresolution)}",
  )
  lines.push(
    "\{prefix}.vertresolution=\{sample_entry_fixed_16_16(v.vertresolution)}",
  )
  lines.push("\{prefix}.frame_count=\{v.frame_count}")
  lines.push("\{prefix}.compressorname=\{sample_entry_hex(v.compressorname)}")
  lines.push(
    "\{prefix}.depth=\{sample_entry_hex_padded(v.depth.to_uint64(), 4)}",
  )
}

///|
fn sample_entry_audio_lines(
  lines : Array[String],
  prefix : String,
  a : @boxes.AudioSampleEntryFields,
) -> Unit {
  lines.push("\{prefix}.data_reference_index=\{a.data_reference_index.get()}")
  lines.push("\{prefix}.channelcount=\{a.channelcount}")
  lines.push("\{prefix}.samplesize=\{a.samplesize}")
  lines.push("\{prefix}.samplerate=\{sample_entry_fixed_16_16(a.samplerate)}")
}

///|
fn sample_entry_byte_list_lines(
  lines : Array[String],
  name : String,
  items : Array[Bytes],
) -> Unit {
  lines.push("\{name}.count=\{items.length()}")
  for i, item in items {
    lines.push("\{name}[\{i}].size=\{item.length()}")
    lines.push("\{name}[\{i}].hex=\{sample_entry_hex(item)}")
  }
}

///|
fn sample_entry_unknown_box_lines(
  lines : Array[String],
  boxes : Array[@boxes.UnknownBox],
) -> Unit {
  lines.push("unknown_boxes.count=\{boxes.length()}")
  for i, b in boxes {
    lines.push(
      "unknown_box[\{i}].type=\{sample_entry_box_type_str(b.box_type)}",
    )
    lines.push("unknown_box[\{i}].payload.size=\{b.payload.length()}")
    lines.push("unknown_box[\{i}].payload.hex=\{sample_entry_hex(b.payload)}")
  }
}

///|
fn sample_entry_avcc_lines(
  lines : Array[String],
  prefix : String,
  b : @boxes.AvccBox,
) -> Unit {
  lines.push("\{prefix}.avc_profile_indication=\{b.avc_profile_indication}")
  lines.push("\{prefix}.profile_compatibility=\{b.profile_compatibility}")
  lines.push("\{prefix}.avc_level_indication=\{b.avc_level_indication}")
  lines.push("\{prefix}.length_size_minus_one=\{b.length_size_minus_one.get()}")
  sample_entry_byte_list_lines(lines, "\{prefix}.sps", b.sps_list)
  sample_entry_byte_list_lines(lines, "\{prefix}.pps", b.pps_list)
  lines.push(
    sample_entry_opt_num(
      "\{prefix}.chroma_format",
      b.chroma_format.map(fn(u) { u.get() }),
    ),
  )
  lines.push(
    sample_entry_opt_num(
      "\{prefix}.bit_depth_luma_minus8",
      b.bit_depth_luma_minus8.map(fn(u) { u.get() }),
    ),
  )
  lines.push(
    sample_entry_opt_num(
      "\{prefix}.bit_depth_chroma_minus8",
      b.bit_depth_chroma_minus8.map(fn(u) { u.get() }),
    ),
  )
  sample_entry_byte_list_lines(lines, "\{prefix}.sps_ext", b.sps_ext_list)
}

///|
fn sample_entry_hvcc_lines(
  lines : Array[String],
  prefix : String,
  b : @boxes.HvccBox,
) -> Unit {
  lines.push("\{prefix}.general_profile_space=\{b.general_profile_space.get()}")
  lines.push("\{prefix}.general_tier_flag=\{b.general_tier_flag.get()}")
  lines.push("\{prefix}.general_profile_idc=\{b.general_profile_idc.get()}")
  lines.push(
    "\{prefix}.general_profile_compatibility_flags=\{sample_entry_hex_padded(b.general_profile_compatibility_flags.to_uint64(), 8)}",
  )
  lines.push(
    "\{prefix}.general_constraint_indicator_flags=\{sample_entry_hex_padded(b.general_constraint_indicator_flags.get(), 12)}",
  )
  lines.push("\{prefix}.general_level_idc=\{b.general_level_idc}")
  lines.push(
    "\{prefix}.min_spatial_segmentation_idc=\{b.min_spatial_segmentation_idc.get()}",
  )
  lines.push("\{prefix}.parallelism_type=\{b.parallelism_type.get()}")
  lines.push("\{prefix}.chroma_format_idc=\{b.chroma_format_idc.get()}")
  lines.push("\{prefix}.bit_depth_luma_minus8=\{b.bit_depth_luma_minus8.get()}")
  lines.push(
    "\{prefix}.bit_depth_chroma_minus8=\{b.bit_depth_chroma_minus8.get()}",
  )
  lines.push("\{prefix}.avg_frame_rate=\{b.avg_frame_rate}")
  lines.push("\{prefix}.constant_frame_rate=\{b.constant_frame_rate.get()}")
  lines.push("\{prefix}.num_temporal_layers=\{b.num_temporal_layers.get()}")
  lines.push("\{prefix}.temporal_id_nested=\{b.temporal_id_nested.get()}")
  lines.push("\{prefix}.length_size_minus_one=\{b.length_size_minus_one.get()}")
  lines.push("\{prefix}.nalu_arrays.count=\{b.nalu_arrays.length()}")
  for i, array in b.nalu_arrays {
    lines.push(
      "\{prefix}.nalu_arrays[\{i}].array_completeness=\{array.array_completeness.get()}",
    )
    lines.push(
      "\{prefix}.nalu_arrays[\{i}].nal_unit_type=\{array.nal_unit_type.get()}",
    )
    sample_entry_byte_list_lines(
      lines,
      "\{prefix}.nalu_arrays[\{i}].nalus",
      array.nalus,
    )
  }
}

///|
fn sample_entry_vpcc_lines(
  lines : Array[String],
  prefix : String,
  b : @boxes.VpccBox,
) -> Unit {
  lines.push("\{prefix}.profile=\{b.profile}")
  lines.push("\{prefix}.level=\{b.level}")
  lines.push("\{prefix}.bit_depth=\{b.bit_depth.get()}")
  lines.push("\{prefix}.chroma_subsampling=\{b.chroma_subsampling.get()}")
  lines.push("\{prefix}.video_full_range_flag=\{b.video_full_range_flag.get()}")
  lines.push("\{prefix}.colour_primaries=\{b.colour_primaries}")
  lines.push("\{prefix}.transfer_characteristics=\{b.transfer_characteristics}")
  lines.push("\{prefix}.matrix_coefficients=\{b.matrix_coefficients}")
  lines.push(
    "\{prefix}.codec_initialization_data.size=\{b.codec_initialization_data.length()}",
  )
  lines.push(
    "\{prefix}.codec_initialization_data.hex=\{sample_entry_hex(b.codec_initialization_data)}",
  )
}

///|
fn sample_entry_av1c_lines(
  lines : Array[String],
  prefix : String,
  b : @boxes.Av1cBox,
) -> Unit {
  lines.push("\{prefix}.seq_profile=\{b.seq_profile.get()}")
  lines.push("\{prefix}.seq_level_idx_0=\{b.seq_level_idx_0.get()}")
  lines.push("\{prefix}.seq_tier_0=\{b.seq_tier_0.get()}")
  lines.push("\{prefix}.high_bitdepth=\{b.high_bitdepth.get()}")
  lines.push("\{prefix}.twelve_bit=\{b.twelve_bit.get()}")
  lines.push("\{prefix}.monochrome=\{b.monochrome.get()}")
  lines.push("\{prefix}.chroma_subsampling_x=\{b.chroma_subsampling_x.get()}")
  lines.push("\{prefix}.chroma_subsampling_y=\{b.chroma_subsampling_y.get()}")
  lines.push(
    "\{prefix}.chroma_sample_position=\{b.chroma_sample_position.get()}",
  )
  lines.push(
    sample_entry_opt_num(
      "\{prefix}.initial_presentation_delay_minus_one",
      b.initial_presentation_delay_minus_one.map(fn(u) { u.get() }),
    ),
  )
  lines.push("\{prefix}.config_obus.size=\{b.config_obus.length()}")
  lines.push("\{prefix}.config_obus.hex=\{sample_entry_hex(b.config_obus)}")
}

///|
fn sample_entry_dops_lines(
  lines : Array[String],
  prefix : String,
  b : @boxes.DopsBox,
) -> Unit {
  lines.push("\{prefix}.output_channel_count=\{b.output_channel_count}")
  lines.push("\{prefix}.pre_skip=\{b.pre_skip}")
  lines.push("\{prefix}.input_sample_rate=\{b.input_sample_rate}")
  lines.push("\{prefix}.output_gain=\{b.output_gain}")
}

///|
fn sample_entry_esds_lines(
  lines : Array[String],
  prefix : String,
  b : @boxes.EsdsBox,
) -> Unit {
  let es = b.es
  lines.push("\{prefix}.es_id=\{es.es_id}")
  lines.push("\{prefix}.stream_priority=\{es.stream_priority.get()}")
  lines.push(
    sample_entry_opt_num(
      "\{prefix}.depends_on_es_id",
      es.depends_on_es_id.map(fn(v) { v.to_uint64() }),
    ),
  )
  let url_str = match es.url_string {
    Some(url) => sample_entry_json_string(url)
    None => "none"
  }
  lines.push("\{prefix}.url_string=\{url_str}")
  lines.push(
    sample_entry_opt_num(
      "\{prefix}.ocr_es_id",
      es.ocr_es_id.map(fn(v) { v.to_uint64() }),
    ),
  )
  let d = es.dec_config_descr
  lines.push(
    "\{prefix}.dec_config.object_type_indication=\{sample_entry_hex_padded(d.object_type_indication.to_uint64(), 2)}",
  )
  lines.push("\{prefix}.dec_config.stream_type=\{d.stream_type.get()}")
  lines.push("\{prefix}.dec_config.up_stream=\{d.up_stream.get()}")
  lines.push("\{prefix}.dec_config.buffer_size_db=\{d.buffer_size_db.get()}")
  lines.push("\{prefix}.dec_config.max_bitrate=\{d.max_bitrate}")
  lines.push("\{prefix}.dec_config.avg_bitrate=\{d.avg_bitrate}")
  match d.dec_specific_info {
    Some(info) => {
      lines.push("\{prefix}.dec_specific_info.size=\{info.payload.length()}")
      lines.push(
        "\{prefix}.dec_specific_info.hex=\{sample_entry_hex(info.payload)}",
      )
    }
    None => lines.push("\{prefix}.dec_specific_info=none")
  }
}

///|
fn sample_entry_dfla_lines(
  lines : Array[String],
  prefix : String,
  b : @boxes.DflaBox,
) -> Unit {
  lines.push("\{prefix}.metadata_blocks.count=\{b.metadata_blocks.length()}")
  for i, block in b.metadata_blocks {
    lines.push(
      "\{prefix}.metadata_blocks[\{i}].last_metadata_block_flag=\{block.last_metadata_block_flag.get()}",
    )
    lines.push(
      "\{prefix}.metadata_blocks[\{i}].block_type=\{block.block_type.get()}",
    )
    lines.push(
      "\{prefix}.metadata_blocks[\{i}].block_data.size=\{block.block_data.length()}",
    )
    lines.push(
      "\{prefix}.metadata_blocks[\{i}].block_data.hex=\{sample_entry_hex(block.block_data)}",
    )
  }
}

///|
/// Rust oracle の `sample-entries` スナップショットと同じ行列を組み立てる。
///
/// 行の順序・書式は issue 0010 で凍結されている。
fn sample_entry_snapshot(entry : @boxes.SampleEntry) -> Array[String] {
  let lines : Array[String] = []
  let variant = match entry {
    Avc1(_) => "avc1"
    Hev1(_) => "hev1"
    Hvc1(_) => "hvc1"
    Vp08(_) => "vp08"
    Vp09(_) => "vp09"
    Av01(_) => "av01"
    Opus(_) => "Opus"
    Mp4a(_) => "mp4a"
    Flac(_) => "fLaC"
    Unknown(_) => "unknown"
  }
  lines.push("variant=\{variant}")
  lines.push(
    "box_type=\{sample_entry_box_type_str(@box.BaseBox::box_type(entry))}",
  )
  lines.push(
    "is_unknown=\{if @box.BaseBox::is_unknown_box(entry) { "true" } else { "false" }}",
  )
  lines.push(
    sample_entry_opt_num(
      "audio_channel_count",
      entry.audio_channel_count().map(fn(v) { v.to_uint64() }),
    ),
  )
  lines.push(
    sample_entry_opt_num(
      "audio_sample_rate",
      entry.audio_sample_rate().map(fn(v) { v.to_uint64() }),
    ),
  )
  lines.push(
    sample_entry_opt_num(
      "audio_sample_size",
      entry.audio_sample_size().map(fn(v) { v.to_uint64() }),
    ),
  )
  let resolution_str = match entry.video_resolution() {
    Some((w, h)) => "\{w}x\{h}"
    None => "none"
  }
  lines.push("video_resolution=\{resolution_str}")
  match entry {
    Avc1(b) => {
      sample_entry_visual_lines(lines, "visual", b.visual)
      sample_entry_avcc_lines(lines, "avcC", b.avcc_box)
      sample_entry_unknown_box_lines(lines, b.unknown_boxes)
    }
    Hev1(b) => {
      sample_entry_visual_lines(lines, "visual", b.visual)
      sample_entry_hvcc_lines(lines, "hvcC", b.hvcc_box)
      sample_entry_unknown_box_lines(lines, b.unknown_boxes)
    }
    Hvc1(b) => {
      sample_entry_visual_lines(lines, "visual", b.visual)
      sample_entry_hvcc_lines(lines, "hvcC", b.hvcc_box)
      sample_entry_unknown_box_lines(lines, b.unknown_boxes)
    }
    Vp08(b) => {
      sample_entry_visual_lines(lines, "visual", b.visual)
      sample_entry_vpcc_lines(lines, "vpcC", b.vpcc_box)
      sample_entry_unknown_box_lines(lines, b.unknown_boxes)
    }
    Vp09(b) => {
      sample_entry_visual_lines(lines, "visual", b.visual)
      sample_entry_vpcc_lines(lines, "vpcC", b.vpcc_box)
      sample_entry_unknown_box_lines(lines, b.unknown_boxes)
    }
    Av01(b) => {
      sample_entry_visual_lines(lines, "visual", b.visual)
      sample_entry_av1c_lines(lines, "av1C", b.av1c_box)
      sample_entry_unknown_box_lines(lines, b.unknown_boxes)
    }
    Opus(b) => {
      sample_entry_audio_lines(lines, "audio", b.audio)
      sample_entry_dops_lines(lines, "dOps", b.dops_box)
      sample_entry_unknown_box_lines(lines, b.unknown_boxes)
    }
    Mp4a(b) => {
      sample_entry_audio_lines(lines, "audio", b.audio)
      sample_entry_esds_lines(lines, "esds", b.esds_box)
      sample_entry_unknown_box_lines(lines, b.unknown_boxes)
    }
    Flac(b) => {
      sample_entry_audio_lines(lines, "audio", b.audio)
      sample_entry_dfla_lines(lines, "dfLa", b.dfla_box)
      sample_entry_unknown_box_lines(lines, b.unknown_boxes)
    }
    Unknown(b) => {
      let size_kind = match b.box_size {
        U32(_) => "u32"
        U64(_) => "u64"
      }
      lines.push("unknown.size_kind=\{size_kind}")
      lines.push("unknown.payload.size=\{b.payload.length()}")
      lines.push("unknown.payload.hex=\{sample_entry_hex(b.payload)}")
    }
  }
  let children = @box.BaseBox::children(entry)
  lines.push("children.count=\{children.length()}")
  for i, child in children {
    lines.push(
      "children[\{i}].type=\{sample_entry_box_type_str(child.box_type())}",
    )
  }
  lines
}

///|
/// oracle の期待スナップショットと MoonBit 側の [`sample_entry_snapshot`] を
/// 比較する。最初に食い違った行だけを報告する。
fn assert_sample_entry_snapshot_matches_oracle(
  label : String,
  expected : Array[String],
  entry : @boxes.SampleEntry,
) -> Unit raise {
  let actual = sample_entry_snapshot(entry)
  if actual.length() != expected.length() {
    fail(
      "\{label}: snapshot line count differs (oracle=\{expected.length()}, moonbit=\{actual.length()})",
    )
  }
  for i in 0..<actual.length() {
    if actual[i] != expected[i] {
      fail(
        "\{label}: snapshot line \{i} differs (oracle=\{expected[i]}, moonbit=\{actual[i]})",
      )
    }
  }
}

///|
test "sample entries match the rust oracle case table" {
  inspect(oracle_sample_entry_cases.length() > 0, content="true")
  for case in oracle_sample_entry_cases {
    let cursor = @bytes.ReadCursor::new(case.input)
    let decoded : @boxes.SampleEntry? = try @bytes.decode_from(cursor) catch {
      @bytes.Mp4Error(kind~, reason~, ..) => {
        if case.ok {
          fail(
            "\{case.name}: oracle succeeded, but moonbit failed with \{oracle_kind_name(kind)}: \{reason}",
          )
        }
        if oracle_kind_name(kind) != case.error_kind {
          fail(
            "\{case.name}: oracle kind \{case.error_kind}, moonbit kind \{oracle_kind_name(kind)} (\{reason})",
          )
        }
        // upstream は insufficient_buffer に理由文を持たない（空文字列）ため、
        // oracle が理由文を持つエラーだけ完全一致を要求する。
        if case.reason != "" && reason != case.reason {
          fail(
            "\{case.name}: oracle reason '\{case.reason}', moonbit reason '\{reason}'",
          )
        }
        None
      }
    } noraise {
      entry => Some(entry)
    }
    match decoded {
      Some(entry) =>
        if case.ok {
          assert_sample_entry_snapshot_matches_oracle(
            case.name,
            case.snapshot,
            entry,
          )
          // 再エンコード比較: oracle がバイト列を返すケースは完全一致、
          // 上流で encode エラーになるケースは同じ kind/reason で失敗すること。
          let encoded : Bytes? = try @bytes.encode_to_bytes(entry) catch {
            @bytes.Mp4Error(kind~, reason~, ..) => {
              if case.encode_error_kind == "" {
                fail(
                  "\{case.name}: oracle encoded successfully, but moonbit encode failed with \{oracle_kind_name(kind)}: \{reason}",
                )
              }
              if oracle_kind_name(kind) != case.encode_error_kind {
                fail(
                  "\{case.name}: oracle encode kind \{case.encode_error_kind}, moonbit kind \{oracle_kind_name(kind)} (\{reason})",
                )
              }
              if case.encode_error_reason != "" &&
                reason != case.encode_error_reason {
                fail(
                  "\{case.name}: oracle encode reason '\{case.encode_error_reason}', moonbit reason '\{reason}'",
                )
              }
              None
            }
          } noraise {
            bytes => Some(bytes)
          }
          match encoded {
            Some(bytes) => {
              if case.encode_error_kind != "" {
                fail(
                  "\{case.name}: oracle encode failed with \{case.encode_error_kind}, but moonbit succeeded",
                )
              }
              if bytes != case.encoded {
                fail(
                  "\{case.name}: encoded bytes differ (oracle=\{case.encoded.length()} bytes, moonbit=\{bytes.length()} bytes)",
                )
              }
            }
            None => ()
          }
        } else {
          fail(
            "\{case.name}: oracle failed with \{case.error_kind}, but moonbit succeeded",
          )
        }
      None => ()
    }
  }
}

///|
test "sample entries match the rust oracle for fixture entries" {
  inspect(oracle_sample_entry_fixtures.length() > 0, content="true")
  for fixture in oracle_sample_entry_fixtures {
    let cursor = @bytes.ReadCursor::new(fixture.input)
    let entry : @boxes.SampleEntry = @bytes.decode_from(cursor)
    inspect(cursor.is_empty(), content="true")
    assert_sample_entry_snapshot_matches_oracle(
      "\{fixture.name} track \{fixture.track_index} entry \{fixture.entry_index}",
      fixture.snapshot,
      entry,
    )
    let encoded = @bytes.encode_to_bytes(entry)
    if encoded != fixture.input {
      fail(
        "\{fixture.name} track \{fixture.track_index} entry \{fixture.entry_index}: re-encoded bytes differ (oracle=\{fixture.input.length()} bytes, moonbit=\{encoded.length()} bytes)",
      )
    }
  }
}
