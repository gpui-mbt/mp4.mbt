///|
/// MPEG-4 ディスクリプターのタグと可変長サイズを読む（上流 `decode_tag_and_size`）。
///
/// サイズは継続ビット（最上位ビット）付きの 7 ビット可変長整数で、先に読む
/// バイトが上位の 7 ビット群になる。上流の "Descriptor size overflow" 検査は
/// シフト量の範囲だけを見ているため `usize` では実際には発火せず、64-bit
/// wrap になる。ここでも `UInt64` の巻き上げで同じ挙動にし、過大サイズは
/// 後続の境界検査で止める。
fn decode_tag_and_size(
  cursor : @bytes.ReadCursor,
) -> (UInt32, UInt64) raise @bytes.Mp4Error {
  let tag = cursor.read_u8()
  let mut size : UInt64 = 0UL
  let mut has_next_byte = true
  while has_next_byte {
    let b = cursor.read_u8()
    has_next_byte = (b & 0x80U) != 0U
    size = (size << 7) | (b & 0x7FU).to_uint64()
  }
  (tag, size)
}

///|
/// タグと可変長サイズを書く（上流 `encode_tag_and_size`）。
///
/// 7 ビット群を上位から並べ、最後の群以外に継続ビットを立てる。
fn write_tag_and_size(
  cursor : @bytes.WriteCursor,
  tag : UInt32,
  size : UInt64,
) -> Unit {
  cursor.write_u8(tag)
  let groups : Array[UInt32] = []
  let mut remaining = size
  let mut first = true
  while true {
    let mut b = (remaining & 0x7FUL).to_uint()
    remaining = remaining >> 7
    if !first {
      b = b | 0x80U
    }
    first = false
    groups.push(b)
    if remaining == 0UL {
      break
    }
  }
  // groups は下位 7 ビット群から順に積んであるため、上位群から書き出す
  for i = groups.length() - 1; i >= 0; i = i - 1 {
    cursor.write_u8(groups[i])
  }
}

///|
/// ペイロードを別カーソルへ先に書いてから、`タグ + 可変長サイズ + ペイロード`
/// を書く（上流 `encode_tag_and_payload`）。
fn write_tagged_payload(
  cursor : @bytes.WriteCursor,
  tag : UInt32,
  write_payload : (@bytes.WriteCursor) -> Unit raise @bytes.Mp4Error,
) -> Unit raise @bytes.Mp4Error {
  let payload = @bytes.WriteCursor::new()
  write_payload(payload)
  write_tag_and_size(cursor, tag, payload.position().to_uint64())
  cursor.write_bytes(payload.to_bytes())
}

///|
/// ディスクリプターのタグが `expected` と一致することを検査する。
fn check_descriptor_tag(
  expected : UInt32,
  actual : UInt32,
) -> Unit raise @bytes.Mp4Error {
  if actual != expected {
    raise @bytes.Mp4Error::invalid_data(
      "Unexpected descriptor tag: expected=\{expected}, actual=\{actual}",
    )
  }
}

///|
/// [ISO_IEC_14496-1] ES_Descriptor class。上流 `EsDescriptor` に対応する。
///
/// `esds` ボックス（[`EsdsBox`]）のペイロードとして decode/encode する。
pub struct EsDescriptor {
  /// ElementaryStream の識別子（0 は予約。実質的な最小値は
  /// [`EsDescriptor::min_es_id`]）
  es_id : UInt32
  /// ストリーム優先度（5 ビット。値が大きいほど優先度が高い）
  stream_priority : @bytes.Uint
  /// このストリームが依存する別 ES の `es_id`
  depends_on_es_id : UInt32?
  /// このストリームの外部データを指す URL（最大 255 バイト）
  url_string : String?
  /// object clock reference を共有する別 ES の `es_id`
  ocr_es_id : UInt32?
  /// このストリームのデコーダー設定
  dec_config_descr : DecoderConfigDescriptor
  /// このストリームの Sync Layer 設定
  sl_config_descr : SlConfigDescriptor
} derive(Eq, Hash, Debug)

///|
pub extend EsDescriptor with Eq::{equal, not_equal}

///|
pub extend EsDescriptor with Hash::{hash, hash_combine}

///|
pub extend EsDescriptor with Debug::{to_repr}

///|
/// [`EsDescriptor::es_id`] の実質的な最小値（0 は予約）。上流 `MIN_ES_ID`。
pub fn EsDescriptor::min_es_id() -> UInt32 {
  1U
}

///|
/// [`EsDescriptor::stream_priority`] で一番優先度が低くなる値。
/// 上流 `LOWEST_STREAM_PRIORITY`。
pub fn EsDescriptor::lowest_stream_priority() -> @bytes.Uint {
  @bytes.Uint::new(0UL, bits=5, offset=0).unwrap()
}

///|
/// 各フィールドを指定して作成する。
pub fn EsDescriptor::new(
  es_id : UInt32,
  stream_priority : @bytes.Uint,
  depends_on_es_id : UInt32?,
  url_string : String?,
  ocr_es_id : UInt32?,
  dec_config_descr : DecoderConfigDescriptor,
  sl_config_descr : SlConfigDescriptor,
) -> EsDescriptor {
  {
    es_id,
    stream_priority,
    depends_on_es_id,
    url_string,
    ocr_es_id,
    dec_config_descr,
    sl_config_descr,
  }
}

///|
/// ディスクリプターをデコードする。
///
/// 上流と同じく、宣言されたディスクリプターサイズは後続フィールドの
/// 読み取り範囲を制限しない（サイズ自体は読み飛ばすだけ）。
pub impl @bytes.Decode for EsDescriptor with fn decode(
  cursor : @bytes.ReadCursor,
) -> EsDescriptor raise @bytes.Mp4Error {
  let (tag, _size) = decode_tag_and_size(cursor)
  check_descriptor_tag(3U, tag)
  let es_id = cursor.read_u16()
  let b = cursor.read_u8().to_uint64()
  let stream_dependence_flag = @bytes.Uint::from_bits(b, bits=1, offset=7)
  let url_flag = @bytes.Uint::from_bits(b, bits=1, offset=6)
  let ocr_stream_flag = @bytes.Uint::from_bits(b, bits=1, offset=5)
  let stream_priority = @bytes.Uint::from_bits(b, bits=5, offset=0)
  let depends_on_es_id = if stream_dependence_flag.get() == 1UL {
    Some(cursor.read_u16())
  } else {
    None
  }
  let url_string = if url_flag.get() == 1UL {
    let len = cursor.read_u8()
    if len.to_uint64() > cursor.remaining().to_uint64() {
      raise @bytes.Mp4Error::invalid_data("URL string exceeds buffer boundary")
    }
    let url_bytes = cursor.read_bytes(len.reinterpret_as_int())
    let url = try @utf8.decode(url_bytes[:]) catch {
      _ => raise @bytes.Mp4Error::invalid_data("Invalid UTF-8 in URL string")
    } noraise {
      text => text
    }
    Some(url)
  } else {
    None
  }
  let ocr_es_id = if ocr_stream_flag.get() == 1UL {
    Some(cursor.read_u16())
  } else {
    None
  }
  let dec_config_descr : DecoderConfigDescriptor = @bytes.decode_from(cursor)
  let sl_config_descr : SlConfigDescriptor = @bytes.decode_from(cursor)
  {
    es_id,
    stream_priority,
    depends_on_es_id,
    url_string,
    ocr_es_id,
    dec_config_descr,
    sl_config_descr,
  }
}

///|
pub extend EsDescriptor with @bytes.Decode::{decode}

///|
/// ディスクリプターをエンコードする（タグ 3 + 可変長サイズ + ペイロード）。
pub impl @bytes.Encode for EsDescriptor with fn encode(
  self : EsDescriptor,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_tagged_payload(cursor, 3U, fn(payload) raise @bytes.Mp4Error {
    payload.write_u16(self.es_id)
    let mut flag_byte = self.stream_priority.to_bits()
    if self.depends_on_es_id is Some(_) {
      flag_byte = flag_byte | 0x80UL
    }
    if self.url_string is Some(_) {
      flag_byte = flag_byte | 0x40UL
    }
    if self.ocr_es_id is Some(_) {
      flag_byte = flag_byte | 0x20UL
    }
    payload.write_u8(flag_byte.to_uint())
    match self.depends_on_es_id {
      Some(es_id) => payload.write_u16(es_id)
      None => ()
    }
    match self.url_string {
      Some(url) => {
        let url_bytes = @utf8.encode(url)
        if url_bytes.length() > 255 {
          raise @bytes.Mp4Error::invalid_input(
            "URL string too long (max 255 bytes)",
          )
        }
        payload.write_u8(url_bytes.length().reinterpret_as_uint())
        payload.write_bytes(url_bytes)
      }
      None => ()
    }
    match self.ocr_es_id {
      Some(es_id) => payload.write_u16(es_id)
      None => ()
    }
    @bytes.Encode::encode(self.dec_config_descr, payload)
    @bytes.Encode::encode(self.sl_config_descr, payload)
  })
}

///|
pub extend EsDescriptor with @bytes.Encode::{encode}

///|
/// [ISO_IEC_14496-1] DecoderConfigDescriptor class。
/// 上流 `DecoderConfigDescriptor` に対応する。
pub struct DecoderConfigDescriptor {
  /// オブジェクトタイプ識別子（例: AAC は
  /// [`DecoderConfigDescriptor::object_type_indication_audio_iso_iec_14496_3`]）
  object_type_indication : UInt32
  /// ストリーム種別（6 ビット。例: 音声は
  /// [`DecoderConfigDescriptor::stream_type_audio`]）
  stream_type : @bytes.Uint
  /// 上り方向ストリームか（1 ビット。再生用ファイルは常に
  /// [`DecoderConfigDescriptor::up_stream_false`]）
  up_stream : @bytes.Uint
  /// デコーダーバッファサイズ（24 ビット、バイト単位）
  buffer_size_db : @bytes.Uint
  /// 最大ビットレート（bps）
  max_bitrate : UInt32
  /// 平均ビットレート（bps。0 は「不明」を意味する）
  avg_bitrate : UInt32
  /// コーデック固有のデコーダー情報（AAC の AudioSpecificConfig 等）
  dec_specific_info : DecoderSpecificInfo?
} derive(Eq, Hash, Debug)

///|
pub extend DecoderConfigDescriptor with Eq::{equal, not_equal}

///|
pub extend DecoderConfigDescriptor with Hash::{hash, hash_combine}

///|
pub extend DecoderConfigDescriptor with Debug::{to_repr}

///|
/// AAC 用の [`DecoderConfigDescriptor::object_type_indication`] の値。
/// 上流 `OBJECT_TYPE_INDICATION_AUDIO_ISO_IEC_14496_3`。
pub fn DecoderConfigDescriptor::object_type_indication_audio_iso_iec_14496_3() -> UInt32 {
  0x40U
}

///|
/// 音声用の [`DecoderConfigDescriptor::stream_type`] の値。
/// 上流 `STREAM_TYPE_AUDIO`。
pub fn DecoderConfigDescriptor::stream_type_audio() -> @bytes.Uint {
  @bytes.Uint::new(0x05UL, bits=6, offset=2).unwrap()
}

///|
/// 通常の再生用メディアファイル向けの [`DecoderConfigDescriptor::up_stream`]
/// の値。上流 `UP_STREAM_FALSE`。
pub fn DecoderConfigDescriptor::up_stream_false() -> @bytes.Uint {
  @bytes.Uint::new(0UL, bits=1, offset=1).unwrap()
}

///|
/// 各フィールドを指定して作成する。
pub fn DecoderConfigDescriptor::new(
  object_type_indication : UInt32,
  stream_type : @bytes.Uint,
  up_stream : @bytes.Uint,
  buffer_size_db : @bytes.Uint,
  max_bitrate : UInt32,
  avg_bitrate : UInt32,
  dec_specific_info : DecoderSpecificInfo?,
) -> DecoderConfigDescriptor {
  {
    object_type_indication,
    stream_type,
    up_stream,
    buffer_size_db,
    max_bitrate,
    avg_bitrate,
    dec_specific_info,
  }
}

///|
/// ディスクリプターをデコードする。
pub impl @bytes.Decode for DecoderConfigDescriptor with fn decode(
  cursor : @bytes.ReadCursor,
) -> DecoderConfigDescriptor raise @bytes.Mp4Error {
  let (tag, _size) = decode_tag_and_size(cursor)
  check_descriptor_tag(4U, tag)
  let object_type_indication = cursor.read_u8()
  let b = cursor.read_u8().to_uint64()
  let stream_type = @bytes.Uint::from_bits(b, bits=6, offset=2)
  let up_stream = @bytes.Uint::from_bits(b, bits=1, offset=1)
  if cursor.remaining() < 3 {
    raise @bytes.Mp4Error::invalid_data(
      "buffer_size_db exceeds buffer boundary",
    )
  }
  let buffer_size_db = @bytes.Uint::from_bits(
    cursor.read_u24().to_uint64(),
    bits=24,
    offset=0,
  )
  let max_bitrate = cursor.read_u32()
  let avg_bitrate = cursor.read_u32()
  let dec_specific_info = if !cursor.is_empty() &&
    cursor.data()[cursor.position()].to_uint() == 5U {
    let info : DecoderSpecificInfo = @bytes.decode_from(cursor)
    Some(info)
  } else {
    None
  }
  {
    object_type_indication,
    stream_type,
    up_stream,
    buffer_size_db,
    max_bitrate,
    avg_bitrate,
    dec_specific_info,
  }
}

///|
pub extend DecoderConfigDescriptor with @bytes.Decode::{decode}

///|
/// ディスクリプターをエンコードする（タグ 4 + 可変長サイズ + ペイロード）。
///
/// 末尾の予約ビット（`up_stream` の後の 1 ビット）は上流と同じく 1 を書く。
pub impl @bytes.Encode for DecoderConfigDescriptor with fn encode(
  self : DecoderConfigDescriptor,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_tagged_payload(cursor, 4U, fn(payload) raise @bytes.Mp4Error {
    payload.write_u8(self.object_type_indication)
    payload.write_u8(
      (self.stream_type.to_bits() | self.up_stream.to_bits() | 1UL).to_uint(),
    )
    payload.write_u24(self.buffer_size_db.get().to_uint())
    payload.write_u32(self.max_bitrate)
    payload.write_u32(self.avg_bitrate)
    match self.dec_specific_info {
      Some(info) => @bytes.Encode::encode(info, payload)
      None => ()
    }
  })
}

///|
pub extend DecoderConfigDescriptor with @bytes.Encode::{encode}

///|
/// [ISO_IEC_14496-1] DecoderSpecificInfo class。上流 `DecoderSpecificInfo` に
/// 対応する。コーデック固有のデコーダー情報（AAC の AudioSpecificConfig 等）
/// を生バイト列として保持する。
pub struct DecoderSpecificInfo {
  /// コーデック固有のバイト列
  payload : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend DecoderSpecificInfo with Eq::{equal, not_equal}

///|
pub extend DecoderSpecificInfo with Hash::{hash, hash_combine}

///|
pub extend DecoderSpecificInfo with Debug::{to_repr}

///|
/// ペイロードを指定して作成する。
pub fn DecoderSpecificInfo::new(payload : Bytes) -> DecoderSpecificInfo {
  { payload, }
}

///|
/// ディスクリプターをデコードする（宣言サイズ分をペイロードとして読む）。
pub impl @bytes.Decode for DecoderSpecificInfo with fn decode(
  cursor : @bytes.ReadCursor,
) -> DecoderSpecificInfo raise @bytes.Mp4Error {
  let (tag, size) = decode_tag_and_size(cursor)
  check_descriptor_tag(5U, tag)
  if size > cursor.remaining().to_uint64() {
    raise @bytes.Mp4Error::invalid_data(
      "DecoderSpecificInfo payload exceeds buffer boundary",
    )
  }
  { payload: cursor.read_bytes(size.to_int()), }
}

///|
pub extend DecoderSpecificInfo with @bytes.Decode::{decode}

///|
/// ディスクリプターをエンコードする（タグ 5 + 可変長サイズ + ペイロード）。
pub impl @bytes.Encode for DecoderSpecificInfo with fn encode(
  self : DecoderSpecificInfo,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_tagged_payload(cursor, 5U, fn(payload) {
    payload.write_bytes(self.payload)
  })
}

///|
pub extend DecoderSpecificInfo with @bytes.Encode::{encode}

///|
/// [ISO_IEC_14496-1] SLConfigDescriptor class。上流 `SlConfigDescriptor` に
/// 対応する（`predefined == 2` の形だけを受理する）。
pub struct SlConfigDescriptor {} derive(Eq, Hash, Debug)

///|
pub extend SlConfigDescriptor with Eq::{equal, not_equal}

///|
pub extend SlConfigDescriptor with Hash::{hash, hash_combine}

///|
pub extend SlConfigDescriptor with Debug::{to_repr}

///|
/// 既定のディスクリプターを作る（`predefined = 2`）。
pub fn SlConfigDescriptor::new() -> SlConfigDescriptor {
  SlConfigDescriptor::{ }
}

///|
/// ディスクリプターをデコードする。`predefined` が 2 以外の場合は
/// [`@bytes.ErrorKind::Unsupported`] で失敗する。
pub impl @bytes.Decode for SlConfigDescriptor with fn decode(
  cursor : @bytes.ReadCursor,
) -> SlConfigDescriptor raise @bytes.Mp4Error {
  let (tag, _size) = decode_tag_and_size(cursor)
  check_descriptor_tag(6U, tag)
  let predefined = cursor.read_u8()
  if predefined != 2U {
    raise @bytes.Mp4Error::unsupported(
      "Unsupported `SLConfigDescriptor.predefined` value: \{predefined}",
    )
  }
  SlConfigDescriptor::{ }
}

///|
pub extend SlConfigDescriptor with @bytes.Decode::{decode}

///|
/// ディスクリプターをエンコードする（タグ 6 + サイズ 1 + `predefined = 2`）。
pub impl @bytes.Encode for SlConfigDescriptor with fn encode(
  _self : SlConfigDescriptor,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_tagged_payload(cursor, 6U, fn(payload) { payload.write_u8(2U) })
}

///|
pub extend SlConfigDescriptor with @bytes.Encode::{encode}
