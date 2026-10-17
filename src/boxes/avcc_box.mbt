///|
/// [ISO/IEC 14496-15] AVCConfigurationBox class (親: [`Avc1Box`])。
/// 上流 `AvccBox` に対応する。
///
/// H.264 のデコーダー設定（AVCDecoderConfigurationRecord）を保持する。
pub struct AvccBox {
  /// H.264 プロファイル識別子（`profile_idc`）
  avc_profile_indication : UInt32
  /// プロファイル互換性フラグ（`constraint_set*_flag` のビット列）
  profile_compatibility : UInt32
  /// H.264 レベル識別子（`level_idc`）
  avc_level_indication : UInt32
  /// NAL ユニット長のバイト数から 1 を引いた値（2 ビット。値 3 は 4 バイト長を表す）
  length_size_minus_one : @bytes.Uint
  /// SPS (Sequence Parameter Set) NAL ユニットのバイト列（最大 31 個）
  sps_list : Array[Bytes]
  /// PPS (Picture Parameter Set) NAL ユニットのバイト列（最大 255 個）
  pps_list : Array[Bytes]
  /// クロマフォーマット（2 ビット）。`avc_profile_indication` が
  /// 66 / 77 / 88 以外の場合のみ ISO/IEC 14496-15 仕様上は必須
  chroma_format : @bytes.Uint?
  /// 輝度のビット深度から 8 を引いた値（3 ビット）。
  /// `chroma_format` と同じ条件で存在する
  bit_depth_luma_minus8 : @bytes.Uint?
  /// 色差のビット深度から 8 を引いた値（3 ビット）。
  /// `chroma_format` と同じ条件で存在する
  bit_depth_chroma_minus8 : @bytes.Uint?
  /// SPS 拡張 NAL ユニットのバイト列（`chroma_format` と同じ条件で存在しうる）
  sps_ext_list : Array[Bytes]
} derive(Eq, Hash, Debug)

///|
pub extend AvccBox with Eq::{equal, not_equal}

///|
pub extend AvccBox with Hash::{hash, hash_combine}

///|
pub extend AvccBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn AvccBox::new(
  avc_profile_indication : UInt32,
  profile_compatibility : UInt32,
  avc_level_indication : UInt32,
  length_size_minus_one : @bytes.Uint,
  sps_list : Array[Bytes],
  pps_list : Array[Bytes],
  chroma_format : @bytes.Uint?,
  bit_depth_luma_minus8 : @bytes.Uint?,
  bit_depth_chroma_minus8 : @bytes.Uint?,
  sps_ext_list : Array[Bytes],
) -> AvccBox {
  {
    avc_profile_indication,
    profile_compatibility,
    avc_level_indication,
    length_size_minus_one,
    sps_list,
    pps_list,
    chroma_format,
    bit_depth_luma_minus8,
    bit_depth_chroma_minus8,
    sps_ext_list,
  }
}

///|
/// `length` が `u16` に収まることを検査し、収まるならその値を返す。
fn checked_u16_length(
  length : Int32,
  too_long : StringView,
) -> UInt32 raise @bytes.Mp4Error {
  if length > 0xFFFF {
    raise @bytes.Mp4Error::invalid_input(too_long)
  }
  length.reinterpret_as_uint()
}

///|
/// `u16` 長の NAL ユニット列（`sps_list` / `pps_list` 相当）を読む。
///
/// `exceeds_message` は上流と同じ境界超過時のエラーメッセージ。
fn read_nal_list(
  payload_cursor : @bytes.ReadCursor,
  count : Int32,
  exceeds_message : StringView,
) -> Array[Bytes] raise @bytes.Mp4Error {
  let list : Array[Bytes] = []
  for _ in 0..<count {
    let size = payload_cursor.read_u16()
    if size.to_uint64() > payload_cursor.remaining().to_uint64() {
      raise @bytes.Mp4Error::invalid_data(exceeds_message)
    }
    list.push(payload_cursor.read_bytes(size.reinterpret_as_int()))
  }
  list
}

///|
/// `u16` 長の NAL ユニット列を書く。
fn write_nal_list(
  payload : @bytes.WriteCursor,
  list : Array[Bytes],
  too_long : StringView,
) -> Unit raise @bytes.Mp4Error {
  for item in list {
    payload.write_u16(checked_u16_length(item.length(), too_long))
    payload.write_bytes(item)
  }
}

///|
/// `avcC` をデコードする。
///
/// `configurationVersion` が 1 でない場合は
/// [`@bytes.ErrorKind::InvalidData`] で失敗する。プロファイルが 66 / 77 / 88
/// 以外の場合の拡張フィールドは、ISO/IEC 14496-15 の仕様上は必須だが、
/// 現実には仕様を守っていないファイルが存在するため、残りペイロードが
/// 空のときは読み取りを省略する（上流と同じ緩和）。
pub impl @bytes.Decode for AvccBox with fn decode(cursor : @bytes.ReadCursor) -> AvccBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(avcc_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(avcc_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let configuration_version = payload_cursor.read_u8()
    if configuration_version != 1U {
      raise @bytes.Mp4Error::invalid_data(
        "Unsupported avcC configuration version: \{configuration_version}",
      )
    }
    let avc_profile_indication = payload_cursor.read_u8()
    let profile_compatibility = payload_cursor.read_u8()
    let avc_level_indication = payload_cursor.read_u8()
    let length_size_minus_one = @bytes.Uint::from_bits(
      payload_cursor.read_u8().to_uint64(),
      bits=2,
      offset=0,
    )
    let sps_count = @bytes.Uint::from_bits(
      payload_cursor.read_u8().to_uint64(),
      bits=5,
      offset=0,
    )
    let sps_list = read_nal_list(
      payload_cursor,
      sps_count.get().to_int(),
      "SPS data exceeds payload boundary",
    )
    let pps_count = payload_cursor.read_u8()
    let pps_list = read_nal_list(
      payload_cursor,
      pps_count.reinterpret_as_int(),
      "PPS data exceeds payload boundary",
    )
    let mut chroma_format : @bytes.Uint? = None
    let mut bit_depth_luma_minus8 : @bytes.Uint? = None
    let mut bit_depth_chroma_minus8 : @bytes.Uint? = None
    let sps_ext_list : Array[Bytes] = []
    if avc_profile_indication != 66U &&
      avc_profile_indication != 77U &&
      avc_profile_indication != 88U &&
      !payload_cursor.is_empty() {
      chroma_format = Some(
        @bytes.Uint::from_bits(
          payload_cursor.read_u8().to_uint64(),
          bits=2,
          offset=0,
        ),
      )
      bit_depth_luma_minus8 = Some(
        @bytes.Uint::from_bits(
          payload_cursor.read_u8().to_uint64(),
          bits=3,
          offset=0,
        ),
      )
      bit_depth_chroma_minus8 = Some(
        @bytes.Uint::from_bits(
          payload_cursor.read_u8().to_uint64(),
          bits=3,
          offset=0,
        ),
      )
      let sps_ext_count = payload_cursor.read_u8()
      for _ in 0..<sps_ext_count.reinterpret_as_int() {
        let size = payload_cursor.read_u16()
        if size.to_uint64() > payload_cursor.remaining().to_uint64() {
          raise @bytes.Mp4Error::invalid_data(
            "SPS EXT data exceeds payload boundary",
          )
        }
        sps_ext_list.push(payload_cursor.read_bytes(size.reinterpret_as_int()))
      }
    }
    {
      avc_profile_indication,
      profile_compatibility,
      avc_level_indication,
      length_size_minus_one,
      sps_list,
      pps_list,
      chroma_format,
      bit_depth_luma_minus8,
      bit_depth_chroma_minus8,
      sps_ext_list,
    }
  })
}

///|
pub extend AvccBox with @bytes.Decode::{decode}

///|
/// `avcC` をエンコードする。`configurationVersion` は常に 1（上流と同じ）。
///
/// プロファイルが 66 / 77 / 88 以外の場合、拡張フィールド
/// （`chroma_format` / `bit_depth_luma_minus8` / `bit_depth_chroma_minus8`）
/// が未設定だと [`@bytes.ErrorKind::InvalidInput`] で失敗する。
pub impl @bytes.Encode for AvccBox with fn encode(
  self : AvccBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, avcc_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    payload.write_u8(1U)
    payload.write_u8(self.avc_profile_indication)
    payload.write_u8(self.profile_compatibility)
    payload.write_u8(self.avc_level_indication)
    payload.write_u8(
      (0b1111_1100UL | self.length_size_minus_one.get()).to_uint(),
    )
    // ISO/IEC 14496-15 の numOfSequenceParameterSets は unsigned int(5) のため最大 31。
    // PPS 側の numOfPictureParameterSets（unsigned int(8)、最大 255）と取り違えないこと。
    if self.sps_list.length() > 31 {
      raise @bytes.Mp4Error::invalid_input("Too many SPSs (max 31)")
    }
    payload.write_u8(
      (0b1110_0000UL | self.sps_list.length().to_uint64()).to_uint(),
    )
    write_nal_list(payload, self.sps_list, "Too long SPS")
    // ISO/IEC 14496-15 の numOfPictureParameterSets は unsigned int(8) のため最大 255。
    if self.pps_list.length() > 255 {
      raise @bytes.Mp4Error::invalid_input("Too many PPSs (max 255)")
    }
    payload.write_u8(self.pps_list.length().reinterpret_as_uint())
    write_nal_list(payload, self.pps_list, "Too long PPS")
    if self.avc_profile_indication != 66U &&
      self.avc_profile_indication != 77U &&
      self.avc_profile_indication != 88U {
      let chroma_format = match self.chroma_format {
        Some(v) => v
        None =>
          raise @bytes.Mp4Error::invalid_input(
            "Missing 'chroma_format' field in 'avcC' box",
          )
      }
      let bit_depth_luma_minus8 = match self.bit_depth_luma_minus8 {
        Some(v) => v
        None =>
          raise @bytes.Mp4Error::invalid_input(
            "Missing 'bit_depth_luma_minus8' field in 'avcC' box",
          )
      }
      let bit_depth_chroma_minus8 = match self.bit_depth_chroma_minus8 {
        Some(v) => v
        None =>
          raise @bytes.Mp4Error::invalid_input(
            "Missing 'bit_depth_chroma_minus8' field in 'avcC' box",
          )
      }
      payload.write_u8((0b1111_1100UL | chroma_format.get()).to_uint())
      payload.write_u8((0b1111_1000UL | bit_depth_luma_minus8.get()).to_uint())
      payload.write_u8(
        (0b1111_1000UL | bit_depth_chroma_minus8.get()).to_uint(),
      )
      if self.sps_ext_list.length() > 255 {
        raise @bytes.Mp4Error::invalid_input("Too many SPS EXTs")
      }
      payload.write_u8(self.sps_ext_list.length().reinterpret_as_uint())
      write_nal_list(payload, self.sps_ext_list, "Too long SPS EXT")
    }
  })
}

///|
pub extend AvccBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for AvccBox with fn box_type(_self) {
  avcc_type()
}

///|
pub impl @box.BaseBox for AvccBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend AvccBox with @box.BaseBox::{box_type, is_unknown_box, children}
