// WebCodecs の H.264 / AV1 出力を MP4 にまとめる browser 用セッション。
//
// DOM / WebCodecs には触れない。JS 側が `VideoEncoder` の出力チャンクと
// `decoderConfig.description` を渡し、ここでは sample entry 構築と
// `Mp4FileMuxer` への追記・finalize だけを行う。

///|
/// 変換セッション。
pub struct WebTranscodeSession {
  priv muxer : @mp4_mux.Mp4FileMuxer
  priv initial : Bytes
  priv mut entry : @boxes.SampleEntry?
  priv width : UInt32
  priv height : UInt32
  priv timescale : @bytes.NonZeroU32
  priv mut payload : Bytes
  priv mut count : UInt32
  priv mut error : String?
}

///|
/// 新しいセッションを作る。
pub fn WebTranscodeSession::new(
  width : UInt32,
  height : UInt32,
  timescale : UInt32,
) -> WebTranscodeSession {
  let muxer = @mp4_mux.Mp4FileMuxer::new() catch {
    _ => abort("Mp4FileMuxer::new must not fail")
  }
  let initial = muxer.initial_boxes_bytes()
  {
    muxer,
    initial,
    entry: None,
    width,
    height,
    timescale: @bytes.NonZeroU32::new(timescale).unwrap(),
    payload: b"",
    count: 0U,
    error: None,
  }
}

///|
/// 現在の状態を返す。
pub fn WebTranscodeSession::state(self : WebTranscodeSession) -> String {
  match self.error {
    Some(_) => "error"
    None => "ready"
  }
}

///|
/// エラー JSON を返す（エラーが無ければ空文字列）。
pub fn WebTranscodeSession::error_json(self : WebTranscodeSession) -> String {
  match self.error {
    Some(message) => error_json_string(message)
    None => ""
  }
}

///|
fn error_json_string(message : String) -> String {
  let builder = StringBuilder()
  builder.write_string("{\"message\":\"")
  builder.write_string(json_escape(message))
  builder.write_string("\"}")
  builder.to_string()
}

///|
/// JSON 文字列用に最低限のエスケープを行う。
fn json_escape(value : String) -> String {
  let builder = StringBuilder()
  for c in value {
    if c == '"' {
      builder.write_string("\\\"")
    } else if c == '\\' {
      builder.write_string("\\\\")
    } else {
      builder.write_char(c)
    }
  }
  builder.to_string()
}

///|
/// avcC のバイト列を解析して `avc1` サンプルエントリーを作る。
///
/// 期待する入力は box header を含まない avcC payload。
pub fn WebTranscodeSession::set_avc(
  self : WebTranscodeSession,
  avcc : Bytes,
) -> Unit {
  if self.entry is Some(_) {
    self.error = Some("sample entry has already been set")
    return
  }
  let parsed = parse_avcc(avcc) catch {
    e => {
      self.error = Some(e.to_string())
      return
    }
  }
  let (profile, compat, level, length_size_minus_one, sps, pps) = parsed
  let config = @bitstream.H264SampleEntryConfig::new(
    @bitstream.LengthSize::from_length_size_minus_one(length_size_minus_one) catch {
      _ => {
        self.error = Some("invalid avcC length size")
        return
      }
    },
  )
  let avc1 = @bitstream.build_avc1_box(sps, pps, config) catch {
    e => {
      self.error = Some(e.to_string())
      return
    }
  }
  // profile/level は build_avc1_box が SPS から写す。avcC 側の値と食い違う場合は
  // SPS を正とする（呼び出し側の description をそのまま信じない）。
  let _ = (profile, compat, level)
  self.entry = Some(@boxes.SampleEntry::Avc1(avc1))
}

///|
/// AV1 の config OBU から `av01` サンプルエントリーを作る。
pub fn WebTranscodeSession::set_av1(
  self : WebTranscodeSession,
  config_obus : Bytes,
) -> Unit {
  if self.entry is Some(_) {
    self.error = Some("sample entry has already been set")
    return
  }
  let av01 = @bitstream.build_av01_box_from_config_obus(
    config_obus,
    self.width,
    self.height,
  ) catch {
    e => {
      self.error = Some(e.to_string())
      return
    }
  }
  self.entry = Some(@boxes.SampleEntry::Av01(av01))
}

///|
/// エンコード済みサンプルを追加する。
pub fn WebTranscodeSession::add_sample(
  self : WebTranscodeSession,
  data : Bytes,
  duration : UInt32,
  keyframe : Bool,
  composition_time_offset : Int64?,
) -> Unit {
  if self.error is Some(_) {
    return
  }
  let entry = match self.entry {
    Some(entry) => entry
    None => {
      self.error = Some("sample entry has not been set")
      return
    }
  }
  let offset = self.initial.length().to_uint64() +
    self.payload.length().to_uint64()
  let sample_entry = if self.count == 0U { Some(entry) } else { None }
  let sample = @mp4_mux.Sample::new(
    @bytes.TrackKind::Video,
    sample_entry,
    keyframe,
    self.timescale,
    duration,
    composition_time_offset,
    offset,
    data.length().reinterpret_as_uint(),
  )
  self.muxer.append_sample(sample) catch {
    e => {
      self.error = Some(e.to_string())
      return
    }
  }
  self.payload = self.payload + data
  self.count = self.count + 1U
}

///|
/// finalize して MP4 全体を base64 で返す。失敗時は空文字列。
pub fn WebTranscodeSession::finalize(self : WebTranscodeSession) -> String {
  if self.error is Some(_) {
    return ""
  }
  if self.entry is None || self.count == 0U {
    self.error = Some("no samples have been added")
    return ""
  }
  let finalized = self.muxer.finalize() catch {
    e => {
      self.error = Some(e.to_string())
      return ""
    }
  }
  let file = build_output(self.initial, self.payload, finalized)
  @base64.encode(file[:])
}

///|
/// avcC payload を解析する。
fn parse_avcc(
  data : Bytes,
) -> (UInt32, UInt32, UInt32, UInt32, Array[Bytes], Array[Bytes]) raise @bytes.Mp4Error {
  if data.length() < 7 {
    raise @bytes.Mp4Error::invalid_input("avcC is too short")
  }
  let cursor = @bytes.ReadCursor::new(data)
  let version = cursor.read_u8()
  if version != 1U {
    raise @bytes.Mp4Error::invalid_input("avcC version must be 1")
  }
  let profile = cursor.read_u8()
  let compat = cursor.read_u8()
  let level = cursor.read_u8()
  let length_size_minus_one = cursor.read_u8() & 0x3U
  let num_sps = cursor.read_u8() & 0x1FU
  let sps : Array[Bytes] = []
  let mut i = 0
  while i < num_sps.reinterpret_as_int() {
    let length = cursor.read_u16()
    sps.push(cursor.read_bytes(length.reinterpret_as_int()))
    i = i + 1
  }
  let num_pps = cursor.read_u8()
  let pps : Array[Bytes] = []
  let mut j = 0
  while j < num_pps.reinterpret_as_int() {
    let length = cursor.read_u16()
    pps.push(cursor.read_bytes(length.reinterpret_as_int()))
    j = j + 1
  }
  (profile, compat, level, length_size_minus_one, sps, pps)
}

///|
/// finalized の差分と payload からファイル bytes を組み立てる。
fn build_output(
  initial : Bytes,
  payload : Bytes,
  finalized : @mp4_mux.FinalizedBoxes,
) -> Bytes {
  let payload_start = initial.length()
  let mdat_offset = finalized.mdat_box_offset().to_int()
  let moov_offset = finalized.moov_box_offset().to_int()
  let moov_size = finalized.moov_box_size()
  let total = if moov_offset >= mdat_offset {
    moov_offset + moov_size
  } else {
    payload_start + payload.length()
  }
  let out = FixedArray::make(total, b'\x00')
  for pair in finalized.offset_and_bytes_pairs() {
    let (offset, bytes) = pair
    let start = offset.to_int()
    for i in 0..<bytes.length() {
      out[start + i] = bytes[i]
    }
  }
  for i in 0..<payload.length() {
    out[payload_start + i] = payload[i]
  }
  Bytes::from_array(out)
}

///|
/// JS からセッションを作る。
#export_name("webtranscode_create")
pub fn webtranscode_create(
  width : UInt32,
  height : UInt32,
  timescale : UInt32,
) -> WebTranscodeSession {
  WebTranscodeSession::new(width, height, timescale)
}

///|
/// avcC を設定する。
#export_name("webtranscode_set_avc")
pub fn webtranscode_set_avc(
  session : WebTranscodeSession,
  avcc : Bytes,
) -> Unit {
  session.set_avc(avcc)
}

///|
/// AV1 config OBU を設定する。
#export_name("webtranscode_set_av1")
pub fn webtranscode_set_av1(
  session : WebTranscodeSession,
  config_obus : Bytes,
) -> Unit {
  session.set_av1(config_obus)
}

///|
/// サンプルを追加する。`cto` は無い場合 `None`。
#export_name("webtranscode_add_sample")
pub fn webtranscode_add_sample(
  session : WebTranscodeSession,
  data : Bytes,
  duration : UInt32,
  keyframe : Bool,
  cto : Int64?,
) -> Unit {
  session.add_sample(data, duration, keyframe, cto)
}

///|
/// finalize して base64 MP4 を返す。
#export_name("webtranscode_finalize")
pub fn webtranscode_finalize(session : WebTranscodeSession) -> String {
  session.finalize()
}

///|
/// 状態を返す。
#export_name("webtranscode_state")
pub fn webtranscode_state(session : WebTranscodeSession) -> String {
  session.state()
}

///|
/// エラー JSON を返す。
#export_name("webtranscode_error_json")
pub fn webtranscode_error_json(session : WebTranscodeSession) -> String {
  session.error_json()
}
