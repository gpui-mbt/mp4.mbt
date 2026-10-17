///|
/// [ISO/IEC 14496-12] FreeSpaceBox（`free`）。
///
/// ペイロードは自由に使えるパディングだが、wire-preserving な再エンコードができる
/// ように保持する（上流 `FreeBox` と同じ）。`skip` は上流と同じくこの型では扱わず、
/// 未知ボックスとして保持される。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x0Cfree\x00\x00\x00\x00")
///   let box : @boxes.FreeBox = @bytes.decode_from(cursor)
///   inspect(box.payload.length(), content="4")
/// }
/// ```
pub struct FreeBox {
  /// この `free` ボックスのペイロード
  payload : Bytes
} derive(Eq, Debug)

///|
pub extend FreeBox with Eq::{equal, not_equal}

///|
pub extend FreeBox with Debug::{to_repr}

///|
/// ペイロード長を指定して作成する。
pub fn FreeBox::new(payload : Bytes) -> FreeBox {
  { payload, }
}

///|
/// `free` をデコードする。ペイロードはコピーして保持し、確保量はカーソルの
/// [`@bytes.ParseLimits`] で制限される。
pub impl @bytes.Decode for FreeBox with fn decode(cursor : @bytes.ReadCursor) -> FreeBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(free_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(free_type())
    { payload: payload_cursor_of(cursor, payload).read_remaining(), }
  })
}

///|
pub extend FreeBox with @bytes.Decode::{decode}

///|
/// `free` を最小幅のサイズでエンコードする。
pub impl @bytes.Encode for FreeBox with fn encode(
  self : FreeBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  let box_size = @box.BoxSize::with_payload_size(
    free_type(),
    self.payload.length().to_uint64(),
  )
  @bytes.Encode::encode(@box.BoxHeader::new(free_type(), box_size), cursor)
  cursor.write_bytes(self.payload)
}

///|
pub extend FreeBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for FreeBox with fn box_type(_self) {
  free_type()
}

///|
pub impl @box.BaseBox for FreeBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend FreeBox with @box.BaseBox::{box_type, is_unknown_box, children}
