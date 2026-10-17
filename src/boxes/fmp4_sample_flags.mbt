///|
/// `trun` / `tfhd` / `trex` で使われるサンプルフラグ（ISO/IEC 14496-12 8.8.3）。
///
/// 上流 `SampleFlags` に対応する 32-bit のビットフィールドである。各フィールドを
/// 取り出すアクセサーと、各フィールドから構築する [`SampleFlags::from_fields`] を持つ。
///
/// ```mbt check
/// test {
///   let flags = @boxes.SampleFlags::from_fields(0, 2, 0, 0, 0, false, 0)
///   inspect(flags.sample_depends_on(), content="2")
///   inspect(flags.sample_is_non_sync_sample(), content="false")
/// }
/// ```
pub struct SampleFlags {
  /// 生の 32-bit 値
  value : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend SampleFlags with Eq::{equal, not_equal}

///|
pub extend SampleFlags with Hash::{hash, hash_combine}

///|
pub extend SampleFlags with Debug::{to_repr}

///|
/// 生の 32-bit 値から作る。
pub fn SampleFlags::new(value : UInt32) -> SampleFlags {
  { value, }
}

///|
/// 全ビットが 0 のフラグを返す。
pub fn SampleFlags::empty() -> SampleFlags {
  { value: 0U, }
}

///|
/// 生の 32-bit 値を返す。
pub fn SampleFlags::get(self : SampleFlags) -> UInt32 {
  self.value
}

///|
/// `is_leading`（2 bits、ビット 27-26）を返す。
pub fn SampleFlags::is_leading(self : SampleFlags) -> UInt32 {
  (self.value >> 26) & 0b11U
}

///|
/// `sample_depends_on`（2 bits、ビット 25-24）を返す。
pub fn SampleFlags::sample_depends_on(self : SampleFlags) -> UInt32 {
  (self.value >> 24) & 0b11U
}

///|
/// `sample_is_depended_on`（2 bits、ビット 23-22）を返す。
pub fn SampleFlags::sample_is_depended_on(self : SampleFlags) -> UInt32 {
  (self.value >> 22) & 0b11U
}

///|
/// `sample_has_redundancy`（2 bits、ビット 21-20）を返す。
pub fn SampleFlags::sample_has_redundancy(self : SampleFlags) -> UInt32 {
  (self.value >> 20) & 0b11U
}

///|
/// `sample_padding_value`（3 bits、ビット 19-17）を返す。
pub fn SampleFlags::sample_padding_value(self : SampleFlags) -> UInt32 {
  (self.value >> 17) & 0b111U
}

///|
/// `sample_is_non_sync_sample`（1 bit、ビット 16）を返す。
pub fn SampleFlags::sample_is_non_sync_sample(self : SampleFlags) -> Bool {
  ((self.value >> 16) & 1U) != 0U
}

///|
/// `sample_degradation_priority`（16 bits、ビット 15-0）を返す。
pub fn SampleFlags::sample_degradation_priority(self : SampleFlags) -> UInt32 {
  self.value & 0xFFFFU
}

///|
/// 各フィールドからサンプルフラグを構築する。
///
/// 各フィールドは対応するビット幅より大きい値を渡しても、ビット幅でマスクされる。
pub fn SampleFlags::from_fields(
  is_leading : UInt32,
  sample_depends_on : UInt32,
  sample_is_depended_on : UInt32,
  sample_has_redundancy : UInt32,
  sample_padding_value : UInt32,
  sample_is_non_sync_sample : Bool,
  sample_degradation_priority : UInt32,
) -> SampleFlags {
  let non_sync : UInt32 = if sample_is_non_sync_sample { 1U } else { 0U }
  {
    value: ((is_leading & 0b11U) << 26) |
    ((sample_depends_on & 0b11U) << 24) |
    ((sample_is_depended_on & 0b11U) << 22) |
    ((sample_has_redundancy & 0b11U) << 20) |
    ((sample_padding_value & 0b111U) << 17) |
    (non_sync << 16) |
    (sample_degradation_priority & 0xFFFFU),
  }
}

///|
pub impl @bytes.Decode for SampleFlags with fn decode(
  cursor : @bytes.ReadCursor,
) -> SampleFlags raise @bytes.Mp4Error {
  { value: cursor.read_u32(), }
}

///|
pub extend SampleFlags with @bytes.Decode::{decode}

///|
pub impl @bytes.Encode for SampleFlags with fn encode(
  self : SampleFlags,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  cursor.write_u32(self.value)
}

///|
pub extend SampleFlags with @bytes.Encode::{encode}
