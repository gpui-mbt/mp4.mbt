///|
/// [ISO/IEC 14496-12] SampleSizeBox（`stsz`）(親: [`StblBox`])。
///
/// 仕様上は 1 つのボックスだが、wire-format の `sample_size` フィールドが非零なら
/// 全サンプル同一サイズ、0 なら per-sample の `entry_size` 配列が後続する、という
/// 2 通りの符号化に分岐する。この分岐を variant で区別する（上流 `StszBox` と
/// 同じ構造）。
///
/// ```mbt check
/// test {
///   let fixed = @boxes.StszBox::Fixed(
///     sample_size=@bytes.NonZeroU32::new(4U).unwrap(),
///     sample_count=2U,
///   )
///   let decoded : @boxes.StszBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(fixed)),
///   )
///   match decoded {
///     @boxes.StszBox::Fixed(sample_size~, sample_count~) => {
///       inspect(sample_size.get(), content="4")
///       inspect(sample_count, content="2")
///     }
///     @boxes.StszBox::Variable(_) => fail("Fixed が得られるはず")
///   }
/// }
/// ```
pub(all) enum StszBox {
  /// 全サンプルが同一サイズの場合（wire-format の `sample_size` が非零）
  Fixed(sample_size~ : @bytes.NonZeroU32, sample_count~ : UInt32)
  /// サンプルごとにサイズが異なる場合（wire-format の `sample_size` が 0 で、
  /// per-sample の `entry_size` 配列が後続する）
  Variable(entry_sizes~ : Array[UInt32])
} derive(Eq, Hash, Debug)

///|
pub extend StszBox with Eq::{equal, not_equal}

///|
pub extend StszBox with Hash::{hash, hash_combine}

///|
pub extend StszBox with Debug::{to_repr}

///|
/// `stsz` をデコードする。
///
/// `sample_size` が 0 の場合は `sample_count` 個の `entry_size` を読んで
/// [`StszBox::Variable`] になる（上流と同じ分岐）。
pub impl @bytes.Decode for StszBox with fn decode(cursor : @bytes.ReadCursor) -> StszBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(stsz_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(stsz_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let sample_size = payload_cursor.read_u32()
    let sample_count = payload_cursor.read_u32()
    match @bytes.NonZeroU32::new(sample_size) {
      Some(sample_size) => Fixed(sample_size~, sample_count~)
      None => {
        let entry_sizes : Array[UInt32] = []
        let mut remaining = sample_count
        while remaining > 0 {
          entry_sizes.push(payload_cursor.read_u32())
          remaining = remaining - 1
        }
        Variable(entry_sizes~)
      }
    }
  })
}

///|
pub extend StszBox with @bytes.Decode::{decode}

///|
/// `stsz` を canonical な形式でエンコードする。
///
/// [`StszBox::Fixed`] は `sample_size.get()` と `sample_count`、
/// [`StszBox::Variable`] は `0` と `entry_sizes` の長さ + 各サイズを書く。
pub impl @bytes.Encode for StszBox with fn encode(
  self : StszBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, stsz_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    match self {
      Fixed(sample_size~, sample_count~) => {
        payload.write_u32(sample_size.get())
        payload.write_u32(sample_count)
      }
      Variable(entry_sizes~) => {
        payload.write_u32(0U)
        payload.write_u32(entry_sizes.length().reinterpret_as_uint())
        for size in entry_sizes {
          payload.write_u32(size)
        }
      }
    }
  })
}

///|
pub extend StszBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for StszBox with fn box_type(_self) {
  stsz_type()
}

///|
pub impl @box.BaseBox for StszBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend StszBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for StszBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for StszBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend StszBox with @box.FullBox::{full_box_version, full_box_flags}
