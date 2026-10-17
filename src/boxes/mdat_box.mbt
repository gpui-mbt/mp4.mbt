///|
/// [ISO/IEC 14496-12] MediaDataBox（`mdat`）のペイロード範囲。
///
/// 上流の `MdatBox` はペイロードをコピーして保持するが、本ポートではファイル内の
/// 位置と長さだけを保持する。demux は範囲参照だけでサンプルを扱えるため、ファイル
/// サイズに比例したメモリを消費しない。
///
/// このため `Encode` は実装しない。可変長ペイロードを書き出したい場合は、上流と
/// 同様に [`@box.BoxHeader`] を直接使う。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::with_config(
///     b"\x00\x00\x00\x0Cmdat\x11\x22\x33\x44",
///     1024UL,
///     @bytes.ParseLimits::default(),
///   )
///   let box : @boxes.MdatBox = @bytes.decode_from(cursor)
///   inspect(box.data_offset, content="1032")
///   inspect(box.data_size, content="4")
/// }
/// ```
pub struct MdatBox {
  /// ペイロード先頭のファイル内位置（ヘッダー直後）
  data_offset : UInt64
  /// ペイロード長
  data_size : UInt64
} derive(Eq, Debug)

///|
pub extend MdatBox with Eq::{equal, not_equal}

///|
pub extend MdatBox with Debug::{to_repr}

///|
/// ペイロード範囲を指定して作成する。
pub fn MdatBox::new(data_offset : UInt64, data_size : UInt64) -> MdatBox {
  { data_offset, data_size, }
}

///|
/// `mdat` をデコードし、ペイロードの範囲だけを記録する。
///
/// ペイロードは view として読み飛ばすだけでコピーしない。`size==0` の場合は
/// カーソル末尾までがペイロードになる（[`@box.BoxHeader::decode_header_and_payload`]
/// と同じ）。
pub impl @bytes.Decode for MdatBox with fn decode(cursor : @bytes.ReadCursor) -> MdatBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(mdat_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(mdat_type())
    {
      data_offset: cursor.offset() - payload.length().to_uint64(),
      data_size: payload.length().to_uint64(),
    }
  })
}

///|
pub extend MdatBox with @bytes.Decode::{decode}

///|
pub impl @box.BaseBox for MdatBox with fn box_type(_self) {
  mdat_type()
}

///|
pub impl @box.BaseBox for MdatBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend MdatBox with @box.BaseBox::{box_type, is_unknown_box, children}
