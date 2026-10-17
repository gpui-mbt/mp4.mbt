///|
/// 4 バイト定数から通常のボックス種別を作る（パッケージ内専用）。
///
/// [`@bytes.FourCC::from_bytes`] は長さを検査するため失敗し得るが、ここへ渡すのは
/// 4 バイトのリテラルだけなので、失敗は定数を書き間違えたときにだけ起きる。
fn normal_box_type(cc : Bytes) -> @bytes.BoxType {
  @bytes.BoxType::Normal(
    @bytes.FourCC::from_bytes(cc) catch {
      _ => abort("box type constant must be exactly 4 bytes")
    },
  )
}

///|
/// `ftyp` のボックス種別。上流の `FtypBox::TYPE` に対応する。
fn ftyp_type() -> @bytes.BoxType {
  normal_box_type(b"ftyp")
}

///|
/// `free` のボックス種別。上流の `FreeBox::TYPE` に対応する。
fn free_type() -> @bytes.BoxType {
  normal_box_type(b"free")
}

///|
/// `mdat` のボックス種別。上流の `MdatBox::TYPE` に対応する。
fn mdat_type() -> @bytes.BoxType {
  normal_box_type(b"mdat")
}

///|
/// `moov` のボックス種別。上流の `MoovBox::TYPE` に対応する。
fn moov_type() -> @bytes.BoxType {
  normal_box_type(b"moov")
}

///|
/// `mvhd` のボックス種別。上流の `MvhdBox::TYPE` に対応する。
fn mvhd_type() -> @bytes.BoxType {
  normal_box_type(b"mvhd")
}

///|
/// `trak` のボックス種別。上流の `TrakBox::TYPE` に対応する。
fn trak_type() -> @bytes.BoxType {
  normal_box_type(b"trak")
}

///|
/// `tkhd` のボックス種別。上流の `TkhdBox::TYPE` に対応する。
fn tkhd_type() -> @bytes.BoxType {
  normal_box_type(b"tkhd")
}

///|
/// `edts` のボックス種別。上流の `EdtsBox::TYPE` に対応する。
fn edts_type() -> @bytes.BoxType {
  normal_box_type(b"edts")
}

///|
/// `elst` のボックス種別。上流の `ElstBox::TYPE` に対応する。
fn elst_type() -> @bytes.BoxType {
  normal_box_type(b"elst")
}

///|
/// `mdia` のボックス種別。上流の `MdiaBox::TYPE` に対応する。
fn mdia_type() -> @bytes.BoxType {
  normal_box_type(b"mdia")
}

///|
/// `mdhd` のボックス種別。上流の `MdhdBox::TYPE` に対応する。
fn mdhd_type() -> @bytes.BoxType {
  normal_box_type(b"mdhd")
}

///|
/// `hdlr` のボックス種別。上流の `HdlrBox::TYPE` に対応する。
fn hdlr_type() -> @bytes.BoxType {
  normal_box_type(b"hdlr")
}

///|
/// `minf` のボックス種別。上流の `MinfBox::TYPE` に対応する。
fn minf_type() -> @bytes.BoxType {
  normal_box_type(b"minf")
}

///|
/// `smhd` のボックス種別。上流の `SmhdBox::TYPE` に対応する。
fn smhd_type() -> @bytes.BoxType {
  normal_box_type(b"smhd")
}

///|
/// `vmhd` のボックス種別。上流の `VmhdBox::TYPE` に対応する。
fn vmhd_type() -> @bytes.BoxType {
  normal_box_type(b"vmhd")
}

///|
/// `sthd` のボックス種別。上流の `SthdBox::TYPE` に対応する。
fn sthd_type() -> @bytes.BoxType {
  normal_box_type(b"sthd")
}

///|
/// `nmhd` のボックス種別。上流の `NmhdBox::TYPE` に対応する。
fn nmhd_type() -> @bytes.BoxType {
  normal_box_type(b"nmhd")
}

///|
/// `dinf` のボックス種別。上流の `DinfBox::TYPE` に対応する。
fn dinf_type() -> @bytes.BoxType {
  normal_box_type(b"dinf")
}

///|
/// `dref` のボックス種別。上流の `DrefBox::TYPE` に対応する。
fn dref_type() -> @bytes.BoxType {
  normal_box_type(b"dref")
}

///|
/// `url ` のボックス種別。上流の `UrlBox::TYPE` に対応する。
fn url_type() -> @bytes.BoxType {
  normal_box_type(b"url ")
}

///|
/// 4 バイト定数から [`@bytes.FourCC`] を作る（パッケージ内専用）。
///
/// `handler_type` のように FourCC をフィールドに持つ型で使う。
/// [`normal_box_type`] と同じく、失敗は定数の書き間違いでしか起きない。
fn fourcc_literal(cc : Bytes) -> @bytes.FourCC {
  @bytes.FourCC::from_bytes(cc) catch {
    _ => abort("fourcc constant must be exactly 4 bytes")
  }
}

///|
/// 必須の子ボックスが無い場合に、上流と同じ理由で失敗させる。
///
/// 上流 `check_mandatory_box` に対応し、理由の文字列も同じ形式
/// （`Missing mandatory '<name>' box in '<parent>' box`）にする。
fn[T] check_mandatory_box(
  box : T?,
  name : StringView,
  parent : StringView,
) -> T raise @bytes.Mp4Error {
  match box {
    Some(child) => child
    None =>
      raise @bytes.Mp4Error::invalid_data(
        "Missing mandatory '\{name}' box in '\{parent}' box",
      )
  }
}

///|
/// 子ボックスのヘッダーだけを読み、位置を戻して種別を返す。
///
/// どの子ボックスが現れたかでディスパッチするコンテナのデコードで使う
/// （上流が `BoxHeader::decode` の結果を見てから各 `decode_at` を呼ぶ流れに対応）。
fn peek_box_type(
  cursor : @bytes.ReadCursor,
) -> @bytes.BoxType raise @bytes.Mp4Error {
  let start = cursor.position()
  let header : @box.BoxHeader = @bytes.decode_from(cursor)
  cursor.rewind_to(start)
  header.box_type()
}

///|
/// 子ボックスを一時カーソルへ書き込んでから、ボックス全体を書き込む。
///
/// 親ボックスの payload 長は子のエンコード結果を見ないと決まらないため、
/// 一時カーソルへ書いてから canonical なサイズ
/// （32-bit に収まるなら [`@box.BoxSize::U32`]）でヘッダーを書く。
/// 上流のコンテナボックスが payload の長さに応じて最小幅を選ぶのと同じ挙動になる。
fn write_box_with_payload(
  cursor : @bytes.WriteCursor,
  box_type : @bytes.BoxType,
  payload : (@bytes.WriteCursor) -> Unit raise @bytes.Mp4Error,
) -> Unit raise @bytes.Mp4Error {
  let payload_cursor = @bytes.WriteCursor::new()
  payload(payload_cursor)
  let box_size = @box.BoxSize::with_payload_size(
    box_type,
    payload_cursor.position().to_uint64(),
  )
  @bytes.Encode::encode(@box.BoxHeader::new(box_type, box_size), cursor)
  cursor.write_bytes(payload_cursor.to_bytes())
}

///|
/// `@box.BoxHeader::decode_header_and_payload` が返した payload view を、
/// 追加のコピーなしで読むカーソルへ変換する。
fn payload_cursor_of(
  cursor : @bytes.ReadCursor,
  payload : BytesView,
) -> @bytes.ReadCursor {
  @bytes.ReadCursor::from_view(
    payload,
    cursor.offset() - payload.length().to_uint64(),
    limits=cursor.limits(),
  )
}
