///|
/// [`SttsBox`] が保持するエントリー。
///
/// 同一の `sample_delta` を持つ連続サンプルを run-length でまとめた 1 区間を表す。
pub struct SttsEntry {
  /// 同じ [`SttsEntry::sample_delta`] を持つ連続サンプル数
  sample_count : UInt32
  /// 各サンプルの尺（[`MdhdBox::timescale`] 単位、すなわち media timescale 単位）
  sample_delta : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend SttsEntry with Eq::{equal, not_equal}

///|
pub extend SttsEntry with Hash::{hash, hash_combine}

///|
pub extend SttsEntry with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn SttsEntry::new(
  sample_count : UInt32,
  sample_delta : UInt32,
) -> SttsEntry {
  { sample_count, sample_delta, }
}

///|
/// [ISO/IEC 14496-12] TimeToSampleBox（`stts`）(親: [`StblBox`])。
///
/// サンプル毎の尺（DTS 差分）を run-length 表現で保持する。上流 `SttsBox` に
/// 対応する。
///
/// ```mbt check
/// test {
///   let box = @boxes.SttsBox::from_sample_deltas([10U, 10U, 20U].iter())
///   inspect(box.entries.length(), content="2")
///   inspect(box.entries[0].sample_count, content="2")
///   let decoded : @boxes.SttsBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.entries[1].sample_delta, content="20")
/// }
/// ```
pub struct SttsBox {
  /// (同尺サンプル数, サンプル尺) の連続を run-length で保持したエントリー列
  entries : Array[SttsEntry]
} derive(Eq, Hash, Debug)

///|
pub extend SttsBox with Eq::{equal, not_equal}

///|
pub extend SttsBox with Hash::{hash, hash_combine}

///|
pub extend SttsBox with Debug::{to_repr}

///|
/// エントリー列を指定して作成する。
pub fn SttsBox::new(entries : Array[SttsEntry]) -> SttsBox {
  { entries, }
}

///|
/// run-length 集約の 1 ステップ。
///
/// 末尾エントリの [`SttsEntry::sample_delta`] が一致するときは `sample_count` を
/// 1 加算し、一致しないときは `sample_count = 1` の新規エントリーを追加する。
/// `sample_count` が `u32::MAX` に達した状態でさらに加算しようとすると
/// [`@bytes.ErrorKind::InvalidData`]（`"stts sample_count overflow"`）で失敗する
/// （上流と同じ理由文字列）。
fn push_sample_delta(
  entries : Array[SttsEntry],
  sample_delta : UInt32,
) -> Unit raise @bytes.Mp4Error {
  match entries.last() {
    Some(last) if last.sample_delta == sample_delta => {
      if last.sample_count == 0xFFFFFFFFU {
        raise @bytes.Mp4Error::invalid_data("stts sample_count overflow")
      }
      let last_index = entries.length() - 1
      entries[last_index] = SttsEntry::new(last.sample_count + 1U, sample_delta)
    }
    _ => entries.push(SttsEntry::new(1U, sample_delta))
  }
}

///|
/// サンプル群の尺を走査するイテレーターから run-length 集約した `stts` を作る。
///
/// 集約規則とオーバーフロー時の挙動は [`push_sample_delta`] を参照。
pub fn SttsBox::from_sample_deltas(
  sample_deltas : Iter[UInt32],
) -> SttsBox raise @bytes.Mp4Error {
  let entries : Array[SttsEntry] = []
  for sample_delta in sample_deltas {
    push_sample_delta(entries, sample_delta)
  }
  { entries, }
}

///|
/// `stts` をデコードする。
pub impl @bytes.Decode for SttsBox with fn decode(cursor : @bytes.ReadCursor) -> SttsBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(stts_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(stts_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let count = payload_cursor.read_u32()
    let entries : Array[SttsEntry] = []
    let mut remaining = count
    while remaining > 0 {
      let sample_count = payload_cursor.read_u32()
      let sample_delta = payload_cursor.read_u32()
      entries.push(SttsEntry::new(sample_count, sample_delta))
      remaining = remaining - 1
    }
    { entries, }
  })
}

///|
pub extend SttsBox with @bytes.Decode::{decode}

///|
/// `stts` を canonical な形式でエンコードする。
pub impl @bytes.Encode for SttsBox with fn encode(
  self : SttsBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, stts_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u32(self.entries.length().reinterpret_as_uint())
    for entry in self.entries {
      payload.write_u32(entry.sample_count)
      payload.write_u32(entry.sample_delta)
    }
  })
}

///|
pub extend SttsBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for SttsBox with fn box_type(_self) {
  stts_type()
}

///|
pub impl @box.BaseBox for SttsBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend SttsBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for SttsBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for SttsBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend SttsBox with @box.FullBox::{full_box_version, full_box_flags}
