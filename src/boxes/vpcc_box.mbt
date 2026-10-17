///|
/// [<https://www.webmproject.org/vp9/mp4/>] VPCodecConfigurationBox class
/// (親: [`Vp08Box`], [`Vp09Box`])。上流 `VpccBox` に対応する。
///
/// VP8 / VP9 のコーデック設定を保持する FullBox（version 1）。
pub struct VpccBox {
  /// VP コーデックのプロファイル
  profile : UInt32
  /// VP コーデックのレベル
  level : UInt32
  /// ビット深度（4 ビット。8 / 10 / 12 のいずれか）
  bit_depth : @bytes.Uint
  /// クロマサブサンプリング（3 ビット）
  chroma_subsampling : @bytes.Uint
  /// 映像レンジフラグ（1 ビット。1 なら full-range、0 なら limited-range）
  video_full_range_flag : @bytes.Uint
  /// 色域（ISO/IEC 23001-8 の `ColourPrimaries`）
  colour_primaries : UInt32
  /// 伝達特性（ISO/IEC 23001-8 の `TransferCharacteristics`）
  transfer_characteristics : UInt32
  /// マトリックス係数（ISO/IEC 23001-8 の `MatrixCoefficients`）
  matrix_coefficients : UInt32
  /// コーデック初期化データ（VP8 / VP9 は仕様上は常に空バイト列）
  codec_initialization_data : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend VpccBox with Eq::{equal, not_equal}

///|
pub extend VpccBox with Hash::{hash, hash_combine}

///|
pub extend VpccBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn VpccBox::new(
  profile : UInt32,
  level : UInt32,
  bit_depth : @bytes.Uint,
  chroma_subsampling : @bytes.Uint,
  video_full_range_flag : @bytes.Uint,
  colour_primaries : UInt32,
  transfer_characteristics : UInt32,
  matrix_coefficients : UInt32,
  codec_initialization_data : Bytes,
) -> VpccBox {
  {
    profile,
    level,
    bit_depth,
    chroma_subsampling,
    video_full_range_flag,
    colour_primaries,
    transfer_characteristics,
    matrix_coefficients,
    codec_initialization_data,
  }
}

///|
/// `vpcC` をデコードする。
///
/// FullBox の version が 1 でない場合は
/// [`@bytes.ErrorKind::InvalidData`] で失敗する（flags は読み飛ばすだけ）。
pub impl @bytes.Decode for VpccBox with fn decode(cursor : @bytes.ReadCursor) -> VpccBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(vpcc_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(vpcc_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    if full_header.version() != 1U {
      raise @bytes.Mp4Error::invalid_data(
        "Unexpected full box header version: box=vpcC, version=\{full_header.version()}",
      )
    }
    let profile = payload_cursor.read_u8()
    let level = payload_cursor.read_u8()
    let b = payload_cursor.read_u8().to_uint64()
    let bit_depth = @bytes.Uint::from_bits(b, bits=4, offset=4)
    let chroma_subsampling = @bytes.Uint::from_bits(b, bits=3, offset=1)
    let video_full_range_flag = @bytes.Uint::from_bits(b, bits=1, offset=0)
    let colour_primaries = payload_cursor.read_u8()
    let transfer_characteristics = payload_cursor.read_u8()
    let matrix_coefficients = payload_cursor.read_u8()
    let codec_init_size = payload_cursor.read_u16()
    if codec_init_size.to_uint64() > payload_cursor.remaining().to_uint64() {
      raise @bytes.Mp4Error::invalid_data(
        "codec initialization data exceeds payload boundary",
      )
    }
    let codec_initialization_data = payload_cursor.read_bytes(
      codec_init_size.reinterpret_as_int(),
    )
    {
      profile,
      level,
      bit_depth,
      chroma_subsampling,
      video_full_range_flag,
      colour_primaries,
      transfer_characteristics,
      matrix_coefficients,
      codec_initialization_data,
    }
  })
}

///|
pub extend VpccBox with @bytes.Decode::{decode}

///|
/// `vpcC` をエンコードする。version 1 / flags 0 の固定値で書く（上流と同じ）。
pub impl @bytes.Encode for VpccBox with fn encode(
  self : VpccBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, vpcc_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    @bytes.Encode::encode(full_header, payload)
    payload.write_u8(self.profile)
    payload.write_u8(self.level)
    payload.write_u8(
      (self.bit_depth.to_bits() |
      self.chroma_subsampling.to_bits() |
      self.video_full_range_flag.to_bits()).to_uint(),
    )
    payload.write_u8(self.colour_primaries)
    payload.write_u8(self.transfer_characteristics)
    payload.write_u8(self.matrix_coefficients)
    if self.codec_initialization_data.length() > 0xFFFF {
      raise @bytes.Mp4Error::invalid_input(
        "codec_initialization_data exceeds u16::MAX",
      )
    }
    payload.write_u16(
      self.codec_initialization_data.length().reinterpret_as_uint(),
    )
    payload.write_bytes(self.codec_initialization_data)
  })
}

///|
pub extend VpccBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for VpccBox with fn box_type(_self) {
  vpcc_type()
}

///|
pub impl @box.BaseBox for VpccBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend VpccBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 常に version 1（上流と同じ）。
pub impl @box.FullBox for VpccBox with fn full_box_version(_self) {
  1U
}

///|
/// 常に flags 0（上流と同じ。デコード時の flags は保持しない）。
pub impl @box.FullBox for VpccBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend VpccBox with @box.FullBox::{full_box_version, full_box_flags}
