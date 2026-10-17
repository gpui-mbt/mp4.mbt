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
