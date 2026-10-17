///|
/// [ISO/IEC 14496-12] FileTypeBox（`ftyp`）。
///
/// ファイルの主要ブランドと、同時に満たすブランド群を保持する。上流の `FtypBox` と
/// `Brand` に対応し、ブランドは 4 バイトの [`@bytes.FourCC`] で表す。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(
///     b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomavc1",
///   )
///   let box : @boxes.FtypBox = @bytes.decode_from(cursor)
///   inspect(box.major_brand.to_string(), content="isom")
///   inspect(box.minor_version, content="512")
///   inspect(box.compatible_brands.length(), content="2")
///   inspect(
///     @bytes.encode_to_bytes(box) ==
///     b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomavc1",
///     content="true",
///   )
/// }
/// ```
pub struct FtypBox {
  /// ファイルの主要な準拠仕様を示すブランド
  major_brand : @bytes.FourCC
  /// `major_brand` のマイナーバージョン
  minor_version : UInt32
  /// このファイルが同時に満たすブランド群
  compatible_brands : Array[@bytes.FourCC]
} derive(Debug)

///|
pub extend FtypBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn FtypBox::new(
  major_brand : @bytes.FourCC,
  minor_version : UInt32,
  compatible_brands : Array[@bytes.FourCC],
) -> FtypBox {
  { major_brand, minor_version, compatible_brands, }
}

///|
/// `ftyp` をデコードする。
///
/// 成功した場合はカーソルがボックス全体の直後へ進む。失敗した場合は
/// カーソル位置を開始位置へ戻す。
pub impl @bytes.Decode for FtypBox with fn decode(cursor : @bytes.ReadCursor) -> FtypBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(ftyp_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(ftyp_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let major_brand = payload_cursor.read_fourcc()
    let minor_version = payload_cursor.read_u32()
    let compatible_brands : Array[@bytes.FourCC] = []
    while !payload_cursor.is_empty() {
      compatible_brands.push(payload_cursor.read_fourcc())
    }
    { major_brand, minor_version, compatible_brands, }
  })
}

///|
pub extend FtypBox with @bytes.Decode::{decode}

///|
/// `ftyp` をエンコードする。
///
/// ペイロード長から最小幅のサイズ（32-bit）を計算して書く。デコード時に
/// largesize 形式だった入力も canonical な 32-bit 形式で書き直される
/// （上流 `FtypBox::encode` と同じ）。
pub impl @bytes.Encode for FtypBox with fn encode(
  self : FtypBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  let payload_size = 4 + 4 + 4 * self.compatible_brands.length()
  let box_size = @box.BoxSize::with_payload_size(
    ftyp_type(),
    payload_size.to_uint64(),
  )
  @bytes.Encode::encode(@box.BoxHeader::new(ftyp_type(), box_size), cursor)
  cursor.write_fourcc(self.major_brand)
  cursor.write_u32(self.minor_version)
  for brand in self.compatible_brands {
    cursor.write_fourcc(brand)
  }
}

///|
pub extend FtypBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for FtypBox with fn box_type(_self) {
  ftyp_type()
}

///|
pub impl @box.BaseBox for FtypBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend FtypBox with @box.BaseBox::{box_type, is_unknown_box, children}
