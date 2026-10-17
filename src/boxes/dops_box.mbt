///|
/// [<https://gitlab.xiph.org/xiph/opus/-/blob/main/doc/opus_in_isobmff.html>]
/// OpusSpecificBox class (親: [`OpusBox`])。上流 `DopsBox` に対応する。
///
/// Opus のデコーダー設定を保持する。
pub struct DopsBox {
  /// Opus のデコード後チャンネル数
  output_channel_count : UInt32
  /// 出力先頭で捨てるサンプル数（48 kHz 基準のサンプル数）
  pre_skip : UInt32
  /// エンコード前のオリジナルのサンプリングレート
  /// （Hz。参考値であり再生には影響しない）
  input_sample_rate : UInt32
  /// 出力ゲイン（Q7.8 固定小数点の dB。復号後に線形スケールで適用する）
  output_gain : Int16
} derive(Eq, Hash, Debug)

///|
pub extend DopsBox with Eq::{equal, not_equal}

///|
pub extend DopsBox with Hash::{hash, hash_combine}

///|
pub extend DopsBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn DopsBox::new(
  output_channel_count : UInt32,
  pre_skip : UInt32,
  input_sample_rate : UInt32,
  output_gain : Int16,
) -> DopsBox {
  { output_channel_count, pre_skip, input_sample_rate, output_gain, }
}

///|
/// `dOps` をデコードする。
///
/// version が 0 でない場合は [`@bytes.ErrorKind::InvalidData`]、
/// `ChannelMappingFamily` が 0 でない場合は
/// [`@bytes.ErrorKind::Unsupported`] で失敗する。
pub impl @bytes.Decode for DopsBox with fn decode(cursor : @bytes.ReadCursor) -> DopsBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(dops_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(dops_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let version = payload_cursor.read_u8()
    if version != 0U {
      raise @bytes.Mp4Error::invalid_data(
        "Unsupported dOps version: \{version}",
      )
    }
    let output_channel_count = payload_cursor.read_u8()
    let pre_skip = payload_cursor.read_u16()
    let input_sample_rate = payload_cursor.read_u32()
    let output_gain = Int16::from_int(payload_cursor.read_i16())
    let channel_mapping_family = payload_cursor.read_u8()
    if channel_mapping_family != 0U {
      raise @bytes.Mp4Error::unsupported(
        "`ChannelMappingFamily != 0` in 'dOps' box is not supported",
      )
    }
    { output_channel_count, pre_skip, input_sample_rate, output_gain, }
  })
}

///|
pub extend DopsBox with @bytes.Decode::{decode}

///|
/// `dOps` をエンコードする。version 0 / `ChannelMappingFamily` 0 の
/// 固定値で書く（上流と同じ）。
pub impl @bytes.Encode for DopsBox with fn encode(
  self : DopsBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, dops_type(), fn(payload) {
    payload.write_u8(0U)
    payload.write_u8(self.output_channel_count)
    payload.write_u16(self.pre_skip)
    payload.write_u32(self.input_sample_rate)
    payload.write_i16(self.output_gain.to_int())
    payload.write_u8(0U)
  })
}

///|
pub extend DopsBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for DopsBox with fn box_type(_self) {
  dops_type()
}

///|
pub impl @box.BaseBox for DopsBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend DopsBox with @box.BaseBox::{box_type, is_unknown_box, children}
