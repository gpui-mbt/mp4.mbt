///|
/// [<https://aomediacodec.github.io/av1-isobmff/>] AV1CodecConfigurationBox class
/// (親: [`Av01Box`])。上流 `Av1cBox` に対応する。
///
/// AV1 のコーデック設定を保持する。
pub struct Av1cBox {
  /// AV1 の `seq_profile`（3 ビット）
  seq_profile : @bytes.Uint
  /// AV1 の `seq_level_idx[0]`（5 ビット）
  seq_level_idx_0 : @bytes.Uint
  /// AV1 の `seq_tier[0]`（1 ビット）
  seq_tier_0 : @bytes.Uint
  /// AV1 の `high_bitdepth`（1 ビット）
  high_bitdepth : @bytes.Uint
  /// AV1 の `twelve_bit`（1 ビット）
  twelve_bit : @bytes.Uint
  /// AV1 の `monochrome`（1 ビット）
  monochrome : @bytes.Uint
  /// AV1 の `subsampling_x`（1 ビット）
  chroma_subsampling_x : @bytes.Uint
  /// AV1 の `subsampling_y`（1 ビット）
  chroma_subsampling_y : @bytes.Uint
  /// AV1 の `chroma_sample_position`（2 ビット）
  chroma_sample_position : @bytes.Uint
  /// AV1 の `initial_presentation_delay_minus_one`（4 ビット。
  /// 存在する場合のみ有効）
  initial_presentation_delay_minus_one : @bytes.Uint?
  /// AV1 の設定 OBU 列（`Sequence Header OBU` などを raw で保持する）
  config_obus : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend Av1cBox with Eq::{equal, not_equal}

///|
pub extend Av1cBox with Hash::{hash, hash_combine}

///|
pub extend Av1cBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn Av1cBox::new(
  seq_profile : @bytes.Uint,
  seq_level_idx_0 : @bytes.Uint,
  seq_tier_0 : @bytes.Uint,
  high_bitdepth : @bytes.Uint,
  twelve_bit : @bytes.Uint,
  monochrome : @bytes.Uint,
  chroma_subsampling_x : @bytes.Uint,
  chroma_subsampling_y : @bytes.Uint,
  chroma_sample_position : @bytes.Uint,
  initial_presentation_delay_minus_one : @bytes.Uint?,
  config_obus : Bytes,
) -> Av1cBox {
  {
    seq_profile,
    seq_level_idx_0,
    seq_tier_0,
    high_bitdepth,
    twelve_bit,
    monochrome,
    chroma_subsampling_x,
    chroma_subsampling_y,
    chroma_sample_position,
    initial_presentation_delay_minus_one,
    config_obus,
  }
}

///|
/// `av1C` をデコードする。
///
/// 先頭バイトの marker が 1 でない場合、または version が 1 でない場合は
/// [`@bytes.ErrorKind::InvalidData`] で失敗する。
pub impl @bytes.Decode for Av1cBox with fn decode(cursor : @bytes.ReadCursor) -> Av1cBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(av1c_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(av1c_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let b = payload_cursor.read_u8().to_uint64()
    let marker = @bytes.Uint::from_bits(b, bits=1, offset=7)
    let version = @bytes.Uint::from_bits(b, bits=7, offset=0)
    if marker.get() != 1UL {
      raise @bytes.Mp4Error::invalid_data("Unexpected av1C marker")
    }
    if version.get() != 1UL {
      raise @bytes.Mp4Error::invalid_data(
        "Unsupported av1C version: \{version.get()}",
      )
    }
    let b = payload_cursor.read_u8().to_uint64()
    let seq_profile = @bytes.Uint::from_bits(b, bits=3, offset=5)
    let seq_level_idx_0 = @bytes.Uint::from_bits(b, bits=5, offset=0)
    let b = payload_cursor.read_u8().to_uint64()
    let seq_tier_0 = @bytes.Uint::from_bits(b, bits=1, offset=7)
    let high_bitdepth = @bytes.Uint::from_bits(b, bits=1, offset=6)
    let twelve_bit = @bytes.Uint::from_bits(b, bits=1, offset=5)
    let monochrome = @bytes.Uint::from_bits(b, bits=1, offset=4)
    let chroma_subsampling_x = @bytes.Uint::from_bits(b, bits=1, offset=3)
    let chroma_subsampling_y = @bytes.Uint::from_bits(b, bits=1, offset=2)
    let chroma_sample_position = @bytes.Uint::from_bits(b, bits=2, offset=0)
    let b = payload_cursor.read_u8().to_uint64()
    let initial_presentation_delay_minus_one = if @bytes.Uint::from_bits(
        b,
        bits=1,
        offset=4,
      ).get() ==
      1UL {
      Some(@bytes.Uint::from_bits(b, bits=4, offset=0))
    } else {
      None
    }
    let config_obus = payload_cursor.read_remaining()
    {
      seq_profile,
      seq_level_idx_0,
      seq_tier_0,
      high_bitdepth,
      twelve_bit,
      monochrome,
      chroma_subsampling_x,
      chroma_subsampling_y,
      chroma_sample_position,
      initial_presentation_delay_minus_one,
      config_obus,
    }
  })
}

///|
pub extend Av1cBox with @bytes.Decode::{decode}

///|
/// `av1C` をエンコードする。marker = 1 / version = 1 の固定値で書く（上流と同じ）。
pub impl @bytes.Encode for Av1cBox with fn encode(
  self : Av1cBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, av1c_type(), fn(payload) {
    // marker (1 ビット = 1) | version (7 ビット = 1)
    payload.write_u8(0b1000_0001U)
    payload.write_u8(
      (self.seq_profile.to_bits() | self.seq_level_idx_0.to_bits()).to_uint(),
    )
    payload.write_u8(
      (self.seq_tier_0.to_bits() |
      self.high_bitdepth.to_bits() |
      self.twelve_bit.to_bits() |
      self.monochrome.to_bits() |
      self.chroma_subsampling_x.to_bits() |
      self.chroma_subsampling_y.to_bits() |
      self.chroma_sample_position.to_bits()).to_uint(),
    )
    match self.initial_presentation_delay_minus_one {
      Some(v) => payload.write_u8((0b1_0000UL | v.to_bits()).to_uint())
      None => payload.write_u8(0U)
    }
    payload.write_bytes(self.config_obus)
  })
}

///|
pub extend Av1cBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for Av1cBox with fn box_type(_self) {
  av1c_type()
}

///|
pub impl @box.BaseBox for Av1cBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend Av1cBox with @box.BaseBox::{box_type, is_unknown_box, children}
