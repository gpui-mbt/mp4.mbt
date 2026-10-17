///|
/// テストで使う Big Endian の `u32` を組み立てる。
fn test_u32(value : UInt32) -> Bytes {
  let cursor = @bytes.WriteCursor::new()
  cursor.write_u32(value)
  cursor.to_bytes()
}

///|
/// テスト用に canonical な（32-bit サイズの）ボックスを組み立てる。
fn test_box_bytes(box_type : Bytes, payload : Bytes) -> Bytes {
  test_u32((8 + payload.length()).reinterpret_as_uint()) + box_type + payload
}

///|
/// テストで使う最小構成の `mvhd`。
fn test_mvhd() -> @boxes.MvhdBox {
  @boxes.MvhdBox::new(
    @bytes.Mp4FileTime::from_secs(0UL),
    @bytes.Mp4FileTime::from_secs(0UL),
    @bytes.NonZeroU32::new(1000U).unwrap(),
    2000UL,
    @boxes.MvhdBox::default_rate(),
    @boxes.MvhdBox::default_volume(),
    @boxes.MvhdBox::default_matrix(),
    1U,
  )
}

///|
/// テストで使う最小構成の `tkhd`。
fn test_tkhd() -> @boxes.TkhdBox {
  @boxes.TkhdBox::new(
    true,
    true,
    false,
    false,
    @bytes.Mp4FileTime::from_secs(0UL),
    @bytes.Mp4FileTime::from_secs(0UL),
    1U,
    1000UL,
    @boxes.TkhdBox::default_layer(),
    @boxes.TkhdBox::default_alternate_group(),
    @boxes.TkhdBox::default_video_volume(),
    @boxes.TkhdBox::default_matrix(),
    @bytes.FixedPointNumber::new(1920, 0),
    @bytes.FixedPointNumber::new(1080, 0),
  )
}

///|
/// テストで使う最小構成の `mdhd`。
fn test_mdhd() -> @boxes.MdhdBox {
  @boxes.MdhdBox::new(
    @bytes.Mp4FileTime::from_secs(0UL),
    @bytes.Mp4FileTime::from_secs(0UL),
    @bytes.NonZeroU32::new(48000U).unwrap(),
    96000UL,
    @bytes.LanguageCode::undefined(),
  )
}

///|
/// テストで使う最小構成の `hdlr`（`vide`、名前なし）。
fn test_hdlr() -> @boxes.HdlrBox {
  @boxes.HdlrBox::new(@boxes.HdlrBox::handler_type_vide(), b"")
}

///|
/// テストで使う最小構成の `minf`（media_header なし、`dinf` は local file）。
fn test_minf() -> @boxes.MinfBox {
  @boxes.MinfBox::new(None, @boxes.DinfBox::local_file(), [])
}

///|
/// テストで使う最小構成の `mdia`。
fn test_mdia() -> @boxes.MdiaBox {
  @boxes.MdiaBox::new(test_mdhd(), test_hdlr(), test_minf(), [])
}

///|
/// テストで使う最小構成の `trak`（`edts` なし）。
fn test_trak() -> @boxes.TrakBox {
  @boxes.TrakBox::new(test_tkhd(), None, test_mdia(), [])
}

///|
/// テストで使う最小構成の `moov`（トラック 1 本）。
fn test_moov() -> @boxes.MoovBox {
  @boxes.MoovBox::new(test_mvhd(), [test_trak()], [])
}

///|
/// テストで使う `vmhd` の canonical なバイト列。
fn test_vmhd_bytes() -> Bytes {
  b"\x00\x00\x00\x14vmhd\x00\x00\x00\x01\x00\x64\x00\xff\x00\x80\x00\x40"
}

///|
/// テストで使う `nmhd` の canonical なバイト列。
fn test_nmhd_bytes() -> Bytes {
  b"\x00\x00\x00\x0Cnmhd\x00\x00\x00\x00"
}

///|
/// テストで使う `stbl` の canonical なバイト列（中身なし）。
fn test_stbl_bytes() -> Bytes {
  test_box_bytes(b"stbl", b"")
}

///|
/// テストで使う未知ボックス（`zzzz`）の canonical なバイト列。
fn test_unknown_bytes() -> Bytes {
  test_box_bytes(b"zzzz", b"\xAA\xBB")
}
