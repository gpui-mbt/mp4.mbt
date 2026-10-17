///|
/// `SampleEntry` から RFC 6381 系の `codecs` パラメーター文字列を生成する。
///
/// 上流 `shiguredo_mp4::codec_string::from_sample_entry` の移植。
/// サンプルエントリーに付属するコーデック設定を読み、各バインディングが定める
/// `codecs` 表記を返す。
///
/// # 対応
///
/// - `Avc1`: `avcC` の profile / compatibility / level を RFC 6381 の
///   3 バイト小文字 hex 表記へ（例: `avc1.640028`）
/// - `Hev1` / `Hvc1`: `hvcC` の `general_*` フィールドから ISO/IEC 14496-15
///   Annex E 形を組み立てる（例: `hev1.1.6.L93.B0`）
/// - `Av01`: `av1C` の必須欄のみから AV1 バインディングの形を組み立てる
///   （例: `av01.0.01M.08`）
/// - `Vp08` / `Vp09`: `vpcC` の profile / level / bit depth から VP
///   バインディングの形を組み立てる（例: `vp09.00.31.08`）
/// - `Mp4a`: `esds` の object type indication に加え、OTI が `0x40` のときは
///   AudioSpecificConfig 先頭から audio object type を読む（例: `mp4a.40.2`）
/// - `Opus` / `fLaC`: バインディングで追加パラメーターが不要なため、
///   サンプルエントリーの 4CC だけを返す（`Opus` / `fLaC`）
///
/// 字幕系（`stpp` / `wvtt` / `tx3g`）は 0010 の時点で `Unknown` として扱われ、
/// 0028 で型付きエントリーに昇格するまでこの関数はエラーを返す。
///
/// # エラー条件
///
/// - `SampleEntry::Unknown`: 未知のサンプルエントリーは解釈できないため
///   [`@bytes.ErrorKind::Unsupported`]
/// - `mp4a` かつ OTI が `0x40` なのに `DecoderSpecificInfo` が欠落、または
///   AOT ビット列が切り詰められている: [`@bytes.ErrorKind::InvalidData`]
///
/// # Examples
///
/// H.264 High Profile Level 4.0 は `avc1.640028` になる:
///
/// ```mbt check
/// test {
///   let entry = @boxes.SampleEntry::Avc1(
///     @boxes.Avc1Box::new(
///       @boxes.VisualSampleEntryFields::new(
///         @boxes.VisualSampleEntryFields::default_data_reference_index(),
///         1920U,
///         1080U,
///         @boxes.VisualSampleEntryFields::default_horizresolution(),
///         @boxes.VisualSampleEntryFields::default_vertresolution(),
///         @boxes.VisualSampleEntryFields::default_frame_count(),
///         @boxes.VisualSampleEntryFields::null_compressorname(),
///         @boxes.VisualSampleEntryFields::default_depth(),
///       ),
///       @boxes.AvccBox::new(
///         100U,
///         0x00U,
///         40U,
///         @bytes.Uint::new(3UL, bits=2, offset=0).unwrap(),
///         [],
///         [],
///         None,
///         None,
///         None,
///         [],
///       ),
///       [],
///     ),
///   )
///   inspect(@codec_string.from_sample_entry(entry), content="avc1.640028")
/// }
/// ```
pub fn from_sample_entry(
  entry : @boxes.SampleEntry,
) -> String raise @bytes.Mp4Error {
  match entry {
    Avc1(b) => avc1_codec_string(b.avcc_box)
    Hev1(b) => hevc_codec_string("hev1", b.hvcc_box)
    Hvc1(b) => hevc_codec_string("hvc1", b.hvcc_box)
    Av01(b) => av01_codec_string(b.av1c_box)
    Vp08(b) => vp_codec_string("vp08", b.vpcc_box)
    Vp09(b) => vp_codec_string("vp09", b.vpcc_box)
    Mp4a(b) => mp4a_codec_string(b.esds_box.es.dec_config_descr)
    Opus(_) => "Opus"
    Flac(_) => "fLaC"
    Unknown(b) =>
      raise @bytes.Mp4Error::unsupported(
        "codec string is unsupported for unknown sample entry type `\{b.box_type.to_string()}`",
      )
  }
}

///|
/// 大文字 16 進 1 桁を返す。
fn hex_upper_digit(n : UInt64) -> Char {
  (if n < 10UL { n + 48UL } else { n + 55UL }).to_byte().to_char()
}

///|
/// 小文字 16 進 1 桁を返す。
fn hex_lower_digit(n : UInt64) -> Char {
  (if n < 10UL { n + 48UL } else { n + 87UL }).to_byte().to_char()
}

///|
/// `value` を `width` 桁の 0 埋め小文字 16 進にする（Rust の `{:0Nx}` と同じ）。
fn hex_lower_padded(value : UInt64, width : Int32) -> String {
  let sb = StringBuilder()
  for i = width - 1; i >= 0; i = i - 1 {
    sb.write_char(hex_lower_digit((value >> (i * 4)) & 0xFUL))
  }
  sb.to_string()
}

///|
/// `value` を `width` 桁の 0 埋め大文字 16 進にする（Rust の `{:0NX}` と同じ）。
fn hex_upper_padded(value : UInt64, width : Int32) -> String {
  let sb = StringBuilder()
  for i = width - 1; i >= 0; i = i - 1 {
    sb.write_char(hex_upper_digit((value >> (i * 4)) & 0xFUL))
  }
  sb.to_string()
}

///|
/// `value` を大文字 16 進にする。先頭の 0 埋めはしない（Rust の `{:X}` と同じ）。
fn hex_upper(value : UInt64) -> String {
  if value == 0UL {
    return "0"
  }
  let digits : Array[Char] = []
  for v = value; v > 0UL; v = v >> 4 {
    digits.push(hex_upper_digit(v & 0xFUL))
  }
  let sb = StringBuilder()
  for i = digits.length() - 1; i >= 0; i = i - 1 {
    sb.write_char(digits[i])
  }
  sb.to_string()
}

///|
/// `value` を `width` 桁の 0 埋め十進にする（Rust の `{:0N}` と同じ）。
fn dec_padded(value : UInt64, width : Int32) -> String {
  let s = value.to_string()
  if s.length() >= width {
    return s
  }
  let sb = StringBuilder()
  for _ in 0..<(width - s.length()) {
    sb.write_char('0')
  }
  sb.write_string(s)
  sb.to_string()
}

///|
/// 32 ビット値をビット反転する（Rust の `u32::reverse_bits` と同じ）。
fn reverse_bits32(value : UInt32) -> UInt32 {
  for i = 0, acc = 0U; i < 32; i = i + 1, acc = (acc << 1) | ((value >> i) & 1U) {

  } nobreak {
    acc
  }
}

///|
/// H.264: `avc1.` + 3 バイト分の小文字 hex（RFC 6381）。
///
/// 上流は `H264ProfileLevelId::to_hex`（`{:02x}{:02x}{:02x}`）を使う。
fn avc1_codec_string(avcc : @boxes.AvccBox) -> String {
  let hex = hex_lower_padded(avcc.avc_profile_indication.to_uint64(), 2) +
    hex_lower_padded(avcc.profile_compatibility.to_uint64(), 2) +
    hex_lower_padded(avcc.avc_level_indication.to_uint64(), 2)
  "avc1.\{hex}"
}

///|
/// HEVC: ISO/IEC 14496-15 Annex E の `codecs` パラメーター。
fn hevc_codec_string(prefix : String, hvcc : @boxes.HvccBox) -> String {
  let space = match hvcc.general_profile_space.get() {
    1UL => "A"
    2UL => "B"
    3UL => "C"
    _ => ""
  }
  let profile_idc = hvcc.general_profile_idc.get()
  let tier = if hvcc.general_tier_flag.get() == 0UL { 'L' } else { 'H' }
  let level = hvcc.general_level_idc

  // general_profile_compatibility_flags を bit-reverse した値の大文字 hex
  //（先頭ゼロ省略可）
  let compat = reverse_bits32(hvcc.general_profile_compatibility_flags)
  let compat_hex = hex_upper(compat.to_uint64())

  // 48 bit の constraint を 6 バイトとし、末尾ゼロを省略する
  //（全ゼロでも最低 1 バイト）
  let flags = hvcc.general_constraint_indicator_flags.get()
  let constraint_bytes : Array[UInt64] = []
  for i in 0..<6 {
    constraint_bytes.push((flags >> ((5 - i) * 8)) & 0xFFUL)
  }
  let mut last_nonzero = 1
  for i in 0..<6 {
    if constraint_bytes[i] != 0UL {
      last_nonzero = i + 1
    }
  }
  let constraint_parts : Array[String] = []
  for i in 0..<last_nonzero {
    constraint_parts.push(hex_upper_padded(constraint_bytes[i], 2))
  }
  let constraint_hex = constraint_parts.join(".")
  "\{prefix}.\{space}\{profile_idc}.\{compat_hex}.\{tier}\{level}.\{constraint_hex}"
}

///|
/// AV1: Binding v1.3.0 Section 5 の必須形のみ。
fn av01_codec_string(av1c : @boxes.Av1cBox) -> String {
  let profile = av1c.seq_profile.get()
  let level = av1c.seq_level_idx_0.get()
  let tier = if av1c.seq_tier_0.get() == 0UL { 'M' } else { 'H' }
  let bit_depth = av1_bit_depth(
    profile,
    av1c.high_bitdepth.get(),
    av1c.twelve_bit.get(),
  )
  "av01.\{profile}.\{dec_padded(level, 2)}\{tier}.\{dec_padded(bit_depth, 2)}"
}

///|
/// AV1 Binding の `BitDepth` を `av1C` の構造化フラグから導出する。
///
/// `seq_profile == 2` かつ `high_bitdepth` なら `twelve_bit` で 12 / 10。
/// それ以外は `high_bitdepth` なら 10、そうでなければ 8。
fn av1_bit_depth(
  seq_profile : UInt64,
  high_bitdepth : UInt64,
  twelve_bit : UInt64,
) -> UInt64 {
  if seq_profile == 2UL && high_bitdepth != 0UL {
    if twelve_bit != 0UL {
      12UL
    } else {
      10UL
    }
  } else if high_bitdepth != 0UL {
    10UL
  } else {
    8UL
  }
}

///|
/// VP8 / VP9: Binding の必須形 `<4CC>.PP.LL.DD` のみ。
fn vp_codec_string(prefix : String, vpcc : @boxes.VpccBox) -> String {
  "\{prefix}.\{dec_padded(vpcc.profile.to_uint64(), 2)}.\{dec_padded(vpcc.level.to_uint64(), 2)}.\{dec_padded(vpcc.bit_depth.get(), 2)}"
}

///|
/// AAC / MPEG-4 Audio: RFC 6381 の `mp4a.<OTI>[.<AOT>]`。
fn mp4a_codec_string(
  dec_config : @boxes.DecoderConfigDescriptor,
) -> String raise @bytes.Mp4Error {
  let oti = dec_config.object_type_indication
  let mut s = "mp4a.\{hex_lower_padded(oti.to_uint64(), 2)}"
  if oti ==
    @boxes.DecoderConfigDescriptor::object_type_indication_audio_iso_iec_14496_3() {
    guard dec_config.dec_specific_info is Some(info) else {
      raise @bytes.Mp4Error::invalid_data(
        "mp4a object type 0x40 requires DecoderSpecificInfo for codecs string",
      )
    }
    let aot = audio_object_type_from_asc(info.payload)
    s = "\{s}.\{aot}"
  }
  s
}

///|
/// AudioSpecificConfig 先頭から `audioObjectType` だけを読む。
///
/// ASC 全体の妥当性（AOT 2 限定など）は検証しない。
fn audio_object_type_from_asc(payload : Bytes) -> UInt64 raise @bytes.Mp4Error {
  if payload.length() == 0 {
    raise @bytes.Mp4Error::invalid_data(
      "AudioSpecificConfig is empty; cannot read audioObjectType",
    )
  }
  let aot = payload[0].to_uint() >> 3
  if aot != 31U {
    return aot.to_uint64()
  }
  // AOT 31 は 5 bit + 続き 6 bit のエスケープ形式（値は 32 + 拡張 6 bit）
  if payload.length() < 2 {
    raise @bytes.Mp4Error::invalid_data(
      "AudioSpecificConfig is truncated at escaped audioObjectType",
    )
  }
  let ext = ((payload[0].to_uint() & 0x07U) << 3) | (payload[1].to_uint() >> 5)
  ext.to_uint64() + 32UL
}
