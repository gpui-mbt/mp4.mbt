///|
/// [`HvccBox`] 内の NAL ユニット配列を保持する構造体。
/// 上流 `HvccNalUintArray` に対応する。
pub struct HvccNalUintArray {
  /// この配列が該当種別の NAL ユニットを網羅しているかを示すフラグ（1 ビット）
  array_completeness : @bytes.Uint
  /// この配列に含まれる NAL ユニットの `nal_unit_type`（6 ビット）
  nal_unit_type : @bytes.Uint
  /// NAL ユニット本体のバイト列
  nalus : Array[Bytes]
} derive(Eq, Hash, Debug)

///|
pub extend HvccNalUintArray with Eq::{equal, not_equal}

///|
pub extend HvccNalUintArray with Hash::{hash, hash_combine}

///|
pub extend HvccNalUintArray with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn HvccNalUintArray::new(
  array_completeness : @bytes.Uint,
  nal_unit_type : @bytes.Uint,
  nalus : Array[Bytes],
) -> HvccNalUintArray {
  { array_completeness, nal_unit_type, nalus, }
}

///|
/// [ISO/IEC 14496-15] HVCConfigurationBox class (親: [`Hev1Box`], [`Hvc1Box`])。
/// 上流 `HvccBox` に対応する。
///
/// H.265 のデコーダー設定（HEVCDecoderConfigurationRecord）を保持する。
pub struct HvccBox {
  /// `general_profile_space`（2 ビット）
  general_profile_space : @bytes.Uint
  /// `general_tier_flag`（1 ビット）
  general_tier_flag : @bytes.Uint
  /// `general_profile_idc`（5 ビット）
  general_profile_idc : @bytes.Uint
  /// `general_profile_compatibility_flags`（32 ビット）
  general_profile_compatibility_flags : UInt32
  /// `general_constraint_indicator_flags`（48 ビット）
  general_constraint_indicator_flags : @bytes.Uint
  /// `general_level_idc`
  general_level_idc : UInt32
  /// `min_spatial_segmentation_idc`（12 ビット）
  min_spatial_segmentation_idc : @bytes.Uint
  /// `parallelism_type`（2 ビット）
  parallelism_type : @bytes.Uint
  /// `chroma_format_idc`（2 ビット）
  chroma_format_idc : @bytes.Uint
  /// 輝度のビット深度から 8 を引いた値（3 ビット）
  bit_depth_luma_minus8 : @bytes.Uint
  /// 色差のビット深度から 8 を引いた値（3 ビット）
  bit_depth_chroma_minus8 : @bytes.Uint
  /// 平均フレームレート（256 秒あたりのフレーム数。0 は未指定）。
  /// ISO/IEC 14496-15:2022 8.3.2.1.3 の `avgFrameRate`
  avg_frame_rate : UInt32
  /// フレームレートが定数かどうか（2 ビット。0 は定フレームレートとは限らない、
  /// 1 は定フレームレート、2 は temporal layer ごとに定フレームレート、3 は予約）。
  /// ISO/IEC 14496-15:2022 8.3.2.1.3 の `constantFrameRate`
  constant_frame_rate : @bytes.Uint
  /// 一時レイヤー数（3 ビット）
  num_temporal_layers : @bytes.Uint
  /// `temporal_id_nested` フラグ（1 ビット）
  temporal_id_nested : @bytes.Uint
  /// NAL ユニット長のバイト数から 1 を引いた値（2 ビット。値 3 は 4 バイト長を表す）
  length_size_minus_one : @bytes.Uint
  /// NAL ユニット種別ごとの配列（VPS / SPS / PPS など）
  nalu_arrays : Array[HvccNalUintArray]
} derive(Eq, Hash, Debug)

///|
pub extend HvccBox with Eq::{equal, not_equal}

///|
pub extend HvccBox with Hash::{hash, hash_combine}

///|
pub extend HvccBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn HvccBox::new(
  general_profile_space : @bytes.Uint,
  general_tier_flag : @bytes.Uint,
  general_profile_idc : @bytes.Uint,
  general_profile_compatibility_flags : UInt32,
  general_constraint_indicator_flags : @bytes.Uint,
  general_level_idc : UInt32,
  min_spatial_segmentation_idc : @bytes.Uint,
  parallelism_type : @bytes.Uint,
  chroma_format_idc : @bytes.Uint,
  bit_depth_luma_minus8 : @bytes.Uint,
  bit_depth_chroma_minus8 : @bytes.Uint,
  avg_frame_rate : UInt32,
  constant_frame_rate : @bytes.Uint,
  num_temporal_layers : @bytes.Uint,
  temporal_id_nested : @bytes.Uint,
  length_size_minus_one : @bytes.Uint,
  nalu_arrays : Array[HvccNalUintArray],
) -> HvccBox {
  {
    general_profile_space,
    general_tier_flag,
    general_profile_idc,
    general_profile_compatibility_flags,
    general_constraint_indicator_flags,
    general_level_idc,
    min_spatial_segmentation_idc,
    parallelism_type,
    chroma_format_idc,
    bit_depth_luma_minus8,
    bit_depth_chroma_minus8,
    avg_frame_rate,
    constant_frame_rate,
    num_temporal_layers,
    temporal_id_nested,
    length_size_minus_one,
    nalu_arrays,
  }
}

///|
/// `hvcC` をデコードする。
///
/// `configurationVersion` が 1 でない場合は
/// [`@bytes.ErrorKind::InvalidData`] で失敗する。
pub impl @bytes.Decode for HvccBox with fn decode(cursor : @bytes.ReadCursor) -> HvccBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(hvcc_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(hvcc_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let configuration_version = payload_cursor.read_u8()
    if configuration_version != 1U {
      raise @bytes.Mp4Error::invalid_data(
        "Unsupported hvcC version: \{configuration_version}",
      )
    }
    let b = payload_cursor.read_u8().to_uint64()
    let general_profile_space = @bytes.Uint::from_bits(b, bits=2, offset=6)
    let general_tier_flag = @bytes.Uint::from_bits(b, bits=1, offset=5)
    let general_profile_idc = @bytes.Uint::from_bits(b, bits=5, offset=0)
    let general_profile_compatibility_flags = payload_cursor.read_u32()
    if payload_cursor.remaining() < 6 {
      raise @bytes.Mp4Error::invalid_data(
        "general_constraint_indicator_flags exceeds payload boundary",
      )
    }
    let constraint_hi = payload_cursor.read_u16().to_uint64()
    let constraint_lo = payload_cursor.read_u32().to_uint64()
    let general_constraint_indicator_flags = @bytes.Uint::from_bits(
      (constraint_hi << 32) | constraint_lo,
      bits=48,
      offset=0,
    )
    let general_level_idc = payload_cursor.read_u8()
    let min_spatial_segmentation_idc = @bytes.Uint::from_bits(
      payload_cursor.read_u16().to_uint64(),
      bits=12,
      offset=0,
    )
    let parallelism_type = @bytes.Uint::from_bits(
      payload_cursor.read_u8().to_uint64(),
      bits=2,
      offset=0,
    )
    let chroma_format_idc = @bytes.Uint::from_bits(
      payload_cursor.read_u8().to_uint64(),
      bits=2,
      offset=0,
    )
    let bit_depth_luma_minus8 = @bytes.Uint::from_bits(
      payload_cursor.read_u8().to_uint64(),
      bits=3,
      offset=0,
    )
    let bit_depth_chroma_minus8 = @bytes.Uint::from_bits(
      payload_cursor.read_u8().to_uint64(),
      bits=3,
      offset=0,
    )
    let avg_frame_rate = payload_cursor.read_u16()
    let b = payload_cursor.read_u8().to_uint64()
    let constant_frame_rate = @bytes.Uint::from_bits(b, bits=2, offset=6)
    let num_temporal_layers = @bytes.Uint::from_bits(b, bits=3, offset=3)
    let temporal_id_nested = @bytes.Uint::from_bits(b, bits=1, offset=2)
    let length_size_minus_one = @bytes.Uint::from_bits(b, bits=2, offset=0)
    let num_of_arrays = payload_cursor.read_u8()
    let nalu_arrays : Array[HvccNalUintArray] = []
    for _ in 0..<num_of_arrays.reinterpret_as_int() {
      let b = payload_cursor.read_u8().to_uint64()
      let array_completeness = @bytes.Uint::from_bits(b, bits=1, offset=7)
      let nal_unit_type = @bytes.Uint::from_bits(b, bits=6, offset=0)
      let num_nalus = payload_cursor.read_u16()
      let nalus : Array[Bytes] = []
      for _ in 0..<num_nalus.reinterpret_as_int() {
        let nal_unit_length = payload_cursor.read_u16()
        if nal_unit_length.to_uint64() > payload_cursor.remaining().to_uint64() {
          raise @bytes.Mp4Error::invalid_data(
            "NAL unit data exceeds payload boundary",
          )
        }
        nalus.push(
          payload_cursor.read_bytes(nal_unit_length.reinterpret_as_int()),
        )
      }
      nalu_arrays.push({ array_completeness, nal_unit_type, nalus, })
    }
    {
      general_profile_space,
      general_tier_flag,
      general_profile_idc,
      general_profile_compatibility_flags,
      general_constraint_indicator_flags,
      general_level_idc,
      min_spatial_segmentation_idc,
      parallelism_type,
      chroma_format_idc,
      bit_depth_luma_minus8,
      bit_depth_chroma_minus8,
      avg_frame_rate,
      constant_frame_rate,
      num_temporal_layers,
      temporal_id_nested,
      length_size_minus_one,
      nalu_arrays,
    }
  })
}

///|
pub extend HvccBox with @bytes.Decode::{decode}

///|
/// `hvcC` をエンコードする。`configurationVersion` は常に 1（上流と同じ）。
pub impl @bytes.Encode for HvccBox with fn encode(
  self : HvccBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, hvcc_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    payload.write_u8(1U)
    payload.write_u8(
      (self.general_profile_space.to_bits() |
      self.general_tier_flag.to_bits() |
      self.general_profile_idc.to_bits()).to_uint(),
    )
    payload.write_u32(self.general_profile_compatibility_flags)
    // 48 ビット値の下位 6 バイト（上流 `to_be_bytes()[2..]`）
    let constraint = self.general_constraint_indicator_flags.get()
    payload.write_u16((constraint >> 32).to_uint())
    payload.write_u32((constraint & 0xFFFF_FFFFUL).to_uint())
    payload.write_u8(self.general_level_idc)
    payload.write_u16(
      (0b1111_0000_0000_0000UL | self.min_spatial_segmentation_idc.to_bits()).to_uint(),
    )
    payload.write_u8(
      (0b1111_1100UL | self.parallelism_type.to_bits()).to_uint(),
    )
    payload.write_u8(
      (0b1111_1100UL | self.chroma_format_idc.to_bits()).to_uint(),
    )
    payload.write_u8(
      (0b1111_1000UL | self.bit_depth_luma_minus8.to_bits()).to_uint(),
    )
    payload.write_u8(
      (0b1111_1000UL | self.bit_depth_chroma_minus8.to_bits()).to_uint(),
    )
    payload.write_u16(self.avg_frame_rate)
    payload.write_u8(
      (self.constant_frame_rate.to_bits() |
      self.num_temporal_layers.to_bits() |
      self.temporal_id_nested.to_bits() |
      self.length_size_minus_one.to_bits()).to_uint(),
    )
    if self.nalu_arrays.length() > 0xFF {
      raise @bytes.Mp4Error::invalid_input(
        "Too many NALU arrays: \{self.nalu_arrays.length()}",
      )
    }
    payload.write_u8(self.nalu_arrays.length().reinterpret_as_uint())
    for nalu_array in self.nalu_arrays {
      payload.write_u8(
        (nalu_array.array_completeness.to_bits() |
        nalu_array.nal_unit_type.to_bits()).to_uint(),
      )
      if nalu_array.nalus.length() > 0xFFFF {
        raise @bytes.Mp4Error::invalid_input(
          "Too many NALUs: \{nalu_array.nalus.length()}",
        )
      }
      payload.write_u16(nalu_array.nalus.length().reinterpret_as_uint())
      for nalu in nalu_array.nalus {
        if nalu.length() > 0xFFFF {
          raise @bytes.Mp4Error::invalid_input(
            "Too large NALU: \{nalu.length()}",
          )
        }
        payload.write_u16(nalu.length().reinterpret_as_uint())
        payload.write_bytes(nalu)
      }
    }
  })
}

///|
pub extend HvccBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for HvccBox with fn box_type(_self) {
  hvcc_type()
}

///|
pub impl @box.BaseBox for HvccBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend HvccBox with @box.BaseBox::{box_type, is_unknown_box, children}
