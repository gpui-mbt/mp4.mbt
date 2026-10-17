///|
/// トラック種別に応じたメディアヘッダーを表す列挙型。
///
/// 上流 `MediaHeader` に対応する。`minf` 直下には仕様上 1 種類しか現れないため、
/// [`MinfBox`] はこの型を `Option` で保持する。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(
///     b"\x00\x00\x00\x14vmhd\x00\x00\x00\x01\x00\x64\x00\xff\x00\x80\x00\x40",
///   )
///   let header : @boxes.MediaHeader = @bytes.decode_from(cursor)
///   match header {
///     @boxes.MediaHeader::Vmhd(vmhd) => {
///       inspect(vmhd.graphicsmode, content="100")
///       inspect(vmhd.opcolor[1], content="128")
///     }
///     _ => fail("vmhd が得られるはず")
///   }
/// }
/// ```
pub(all) enum MediaHeader {
  /// 音声トラック用（`smhd`）
  Smhd(SmhdBox)
  /// 映像トラック用（`vmhd`）
  Vmhd(VmhdBox)
  /// 字幕トラック用（`sthd`）
  Sthd(SthdBox)
  /// 汎用トラック用（`nmhd`。ヒントトラック等で使われる）
  Nmhd(NmhdBox)
} derive(Eq, Hash, Debug)

///|
pub extend MediaHeader with Eq::{equal, not_equal}

///|
pub extend MediaHeader with Hash::{hash, hash_combine}

///|
pub extend MediaHeader with Debug::{to_repr}

///|
/// 先頭の子ボックスの種別を見て対応する型でデコードする。
///
/// 4 種類（`smhd` / `vmhd` / `sthd` / `nmhd`）以外の種別は
/// [`@bytes.ErrorKind::InvalidData`] で拒否する
/// （`SampleEntry` のような未知種別フォールバックは持たない）。
pub impl @bytes.Decode for MediaHeader with fn decode(
  cursor : @bytes.ReadCursor,
) -> MediaHeader raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  let box_type = peek_box_type(cursor)
  if box_type == smhd_type() {
    MediaHeader::Smhd(@bytes.decode_from(cursor))
  } else if box_type == vmhd_type() {
    MediaHeader::Vmhd(@bytes.decode_from(cursor))
  } else if box_type == sthd_type() {
    MediaHeader::Sthd(@bytes.decode_from(cursor))
  } else if box_type == nmhd_type() {
    MediaHeader::Nmhd(@bytes.decode_from(cursor))
  } else {
    raise @bytes.Mp4Error::invalid_data(
      "unexpected box type for MediaHeader: \{box_type.to_string()}",
    )
  }
}

///|
pub extend MediaHeader with @bytes.Decode::{decode}

///|
/// 内包するボックスをそのままエンコードする。
pub impl @bytes.Encode for MediaHeader with fn encode(
  self : MediaHeader,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  match self {
    Smhd(b) => @bytes.Encode::encode(b, cursor)
    Vmhd(b) => @bytes.Encode::encode(b, cursor)
    Sthd(b) => @bytes.Encode::encode(b, cursor)
    Nmhd(b) => @bytes.Encode::encode(b, cursor)
  }
}

///|
pub extend MediaHeader with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MediaHeader with fn box_type(self) {
  match self {
    Smhd(b) => @box.BaseBox::box_type(b)
    Vmhd(b) => @box.BaseBox::box_type(b)
    Sthd(b) => @box.BaseBox::box_type(b)
    Nmhd(b) => @box.BaseBox::box_type(b)
  }
}

///|
pub impl @box.BaseBox for MediaHeader with fn children(self) {
  match self {
    Smhd(b) => @box.BaseBox::children(b)
    Vmhd(b) => @box.BaseBox::children(b)
    Sthd(b) => @box.BaseBox::children(b)
    Nmhd(b) => @box.BaseBox::children(b)
  }
}

///|
pub extend MediaHeader with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// [ISO/IEC 14496-12] SoundMediaHeaderBox（`smhd`）(親: [`MinfBox`])。
///
/// 音声トラックのバランスを保持する。上流 `SmhdBox` に対応する。
/// `balance` は上流では符号なし 8.8 固定小数点
/// （[`@bytes.FixedPointNumber`] の整数部を生バイトとして読む）。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(
///     b"\x00\x00\x00\x10smhd\x00\x00\x00\x00\x01\x80\x00\x00",
///   )
///   let box : @boxes.SmhdBox = @bytes.decode_from(cursor)
///   inspect(box.balance.integer(), content="1")
///   inspect(box.balance.fraction(), content="128")
///   inspect(
///     @bytes.encode_to_bytes(box) == cursor.data().to_owned(),
///     content="true",
///   )
/// }
/// ```
pub struct SmhdBox {
  /// ステレオ音声の左右バランス（0.0 が中央、-1.0 が全左、+1.0 が全右）
  balance : @bytes.FixedPointNumber
} derive(Eq, Hash, Debug)

///|
pub extend SmhdBox with Eq::{equal, not_equal}

///|
pub extend SmhdBox with Hash::{hash, hash_combine}

///|
pub extend SmhdBox with Debug::{to_repr}

///|
/// バランスを指定して作成する。
pub fn SmhdBox::new(balance : @bytes.FixedPointNumber) -> SmhdBox {
  { balance, }
}

///|
/// [`SmhdBox::balance`] のデフォルト値（中央）。
pub fn SmhdBox::default_balance() -> @bytes.FixedPointNumber {
  @bytes.FixedPointNumber::new(0, 0)
}

///|
/// `smhd` をデコードする。`balance` は符号なし 8.8 として読む。
pub impl @bytes.Decode for SmhdBox with fn decode(cursor : @bytes.ReadCursor) -> SmhdBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(smhd_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(smhd_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let balance = payload_cursor.read_fixed_8_8_unsigned()
    // reserved（2 バイト）
    payload_cursor.skip(2)
    { balance, }
  })
}

///|
pub extend SmhdBox with @bytes.Decode::{decode}

///|
/// `smhd` をエンコードする。`balance` は符号なし 8.8 として書く。
pub impl @bytes.Encode for SmhdBox with fn encode(
  self : SmhdBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, smhd_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_fixed_8_8_unsigned(self.balance)
    payload.write_u16(0)
  })
}

///|
pub extend SmhdBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for SmhdBox with fn box_type(_self) {
  smhd_type()
}

///|
pub impl @box.BaseBox for SmhdBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend SmhdBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 常に version 0（上流と同じ）。
pub impl @box.FullBox for SmhdBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for SmhdBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend SmhdBox with @box.FullBox::{full_box_version, full_box_flags}

///|
/// [ISO/IEC 14496-12] VideoMediaHeaderBox（`vmhd`）(親: [`MinfBox`])。
///
/// 映像トラックの合成モードと色を保持する。上流 `VmhdBox` に対応する。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(
///     b"\x00\x00\x00\x14vmhd\x00\x00\x00\x01\x00\x64\x00\xff\x00\x80\x00\x40",
///   )
///   let box : @boxes.VmhdBox = @bytes.decode_from(cursor)
///   inspect(box.graphicsmode, content="100")
///   inspect(box.opcolor[0], content="255")
///   inspect(
///     @bytes.encode_to_bytes(box) == cursor.data().to_owned(),
///     content="true",
///   )
/// }
/// ```
pub struct VmhdBox {
  /// 映像合成モード（0: コピー。ほとんどのファイルは 0 を用いる）
  graphicsmode : UInt16
  /// [`VmhdBox::graphicsmode`] の合成で使う RGB 色（0..=65535 の 16 ビット値 × 3）
  opcolor : Array[UInt16]
} derive(Eq, Hash, Debug)

///|
pub extend VmhdBox with Eq::{equal, not_equal}

///|
pub extend VmhdBox with Hash::{hash, hash_combine}

///|
pub extend VmhdBox with Debug::{to_repr}

///|
/// 合成モードと色を指定して作成する。
pub fn VmhdBox::new(graphicsmode : UInt16, opcolor : Array[UInt16]) -> VmhdBox {
  { graphicsmode, opcolor, }
}

///|
/// [`VmhdBox::graphicsmode`] のデフォルト値（コピー）。
pub fn VmhdBox::default_graphicsmode() -> UInt16 {
  0
}

///|
/// [`VmhdBox::opcolor`] のデフォルト値。
pub fn VmhdBox::default_opcolor() -> Array[UInt16] {
  [0, 0, 0]
}

///|
/// `vmhd` をデコードする。
///
/// ISO/IEC 14496-12 には「`vmhd` の flags は 1」と記載があるが、実際には 0 の
/// ファイルも存在するため、flags の検査は行わない（上流と同じ）。
pub impl @bytes.Decode for VmhdBox with fn decode(cursor : @bytes.ReadCursor) -> VmhdBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(vmhd_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(vmhd_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let graphicsmode = payload_cursor.read_u16().to_uint16()
    let opcolor : Array[UInt16] = []
    for _ in 0..<3 {
      opcolor.push(payload_cursor.read_u16().to_uint16())
    }
    { graphicsmode, opcolor, }
  })
}

///|
pub extend VmhdBox with @bytes.Decode::{decode}

///|
/// `vmhd` をエンコードする。flags は仕様に従い 1 を書く（上流と同じ）。
pub impl @bytes.Encode for VmhdBox with fn encode(
  self : VmhdBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, vmhd_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u16(self.graphicsmode.to_uint())
    for color in self.opcolor {
      payload.write_u16(color.to_uint())
    }
  })
}

///|
pub extend VmhdBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for VmhdBox with fn box_type(_self) {
  vmhd_type()
}

///|
pub impl @box.BaseBox for VmhdBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend VmhdBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 常に version 0（上流と同じ）。
pub impl @box.FullBox for VmhdBox with fn full_box_version(_self) {
  0U
}

///|
/// 仕様どおり flags 1 を書く（上流 `VmhdBox` の `full_box_flags` と同じ）。
pub impl @box.FullBox for VmhdBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(1)
}

///|
pub extend VmhdBox with @box.FullBox::{full_box_version, full_box_flags}

///|
/// [ISO/IEC 14496-12] SubtitleMediaHeaderBox（`sthd`）(親: [`MinfBox`])。
///
/// 字幕トラックの `minf` 直下に配置されるメディアヘッダーボックス。
/// version 0 の FullBox のみで追加ペイロードは持たない（上流と同じ）。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x0Csthd\x00\x00\x00\x00")
///   let box : @boxes.SthdBox = @bytes.decode_from(cursor)
///   inspect(box == @boxes.SthdBox::new(), content="true")
///   inspect(
///     @bytes.encode_to_bytes(box) == cursor.data().to_owned(),
///     content="true",
///   )
/// }
/// ```
pub struct SthdBox {} derive(Eq, Hash, Debug)

///|
pub extend SthdBox with Eq::{equal, not_equal}

///|
pub extend SthdBox with Hash::{hash, hash_combine}

///|
pub extend SthdBox with Debug::{to_repr}

///|
/// 値を作る（フィールドを持たない）。
pub fn SthdBox::new() -> SthdBox {
  SthdBox::{ }
}

///|
/// `sthd` をデコードする。FullBox ヘッダー以外にフィールドはない。
pub impl @bytes.Decode for SthdBox with fn decode(cursor : @bytes.ReadCursor) -> SthdBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(sthd_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(sthd_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    SthdBox::{ }
  })
}

///|
pub extend SthdBox with @bytes.Decode::{decode}

///|
/// `sthd` をエンコードする。
pub impl @bytes.Encode for SthdBox with fn encode(
  self : SthdBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, sthd_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
  })
}

///|
pub extend SthdBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for SthdBox with fn box_type(_self) {
  sthd_type()
}

///|
pub impl @box.BaseBox for SthdBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend SthdBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 常に version 0（上流と同じ）。
pub impl @box.FullBox for SthdBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for SthdBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend SthdBox with @box.FullBox::{full_box_version, full_box_flags}

///|
/// [ISO/IEC 14496-12] NullMediaHeaderBox（`nmhd`）(親: [`MinfBox`])。
///
/// メディアハンドラーに対応するメディアヘッダーが特にない場合に置かれる汎用ボックス。
/// 字幕トラック（例えば `tx3g`）だけでなくヒントトラック等でも使われる。
/// version 0 の FullBox のみで追加ペイロードは持たない（上流と同じ）。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x0Cnmhd\x00\x00\x00\x00")
///   let box : @boxes.NmhdBox = @bytes.decode_from(cursor)
///   inspect(box == @boxes.NmhdBox::new(), content="true")
///   inspect(
///     @bytes.encode_to_bytes(box) == cursor.data().to_owned(),
///     content="true",
///   )
/// }
/// ```
pub struct NmhdBox {} derive(Eq, Hash, Debug)

///|
pub extend NmhdBox with Eq::{equal, not_equal}

///|
pub extend NmhdBox with Hash::{hash, hash_combine}

///|
pub extend NmhdBox with Debug::{to_repr}

///|
/// 値を作る（フィールドを持たない）。
pub fn NmhdBox::new() -> NmhdBox {
  NmhdBox::{ }
}

///|
/// `nmhd` をデコードする。FullBox ヘッダー以外にフィールドはない。
pub impl @bytes.Decode for NmhdBox with fn decode(cursor : @bytes.ReadCursor) -> NmhdBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(nmhd_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(nmhd_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    NmhdBox::{ }
  })
}

///|
pub extend NmhdBox with @bytes.Decode::{decode}

///|
/// `nmhd` をエンコードする。
pub impl @bytes.Encode for NmhdBox with fn encode(
  self : NmhdBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, nmhd_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
  })
}

///|
pub extend NmhdBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for NmhdBox with fn box_type(_self) {
  nmhd_type()
}

///|
pub impl @box.BaseBox for NmhdBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend NmhdBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 常に version 0（上流と同じ）。
pub impl @box.FullBox for NmhdBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for NmhdBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend NmhdBox with @box.FullBox::{full_box_version, full_box_flags}
