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
/// `stbl` のボックス種別。上流 `StblBox::TYPE` に対応する。
fn stbl_type() -> @bytes.BoxType {
  normal_box_type(b"stbl")
}

///|
/// `stsd` のボックス種別。上流 `StsdBox::TYPE` に対応する。
fn stsd_type() -> @bytes.BoxType {
  normal_box_type(b"stsd")
}

///|
/// `stts` のボックス種別。上流 `SttsBox::TYPE` に対応する。
fn stts_type() -> @bytes.BoxType {
  normal_box_type(b"stts")
}

///|
/// `ctts` のボックス種別。上流 `CttsBox::TYPE` に対応する。
fn ctts_type() -> @bytes.BoxType {
  normal_box_type(b"ctts")
}

///|
/// `cslg` のボックス種別。上流 `CslgBox::TYPE` に対応する。
fn cslg_type() -> @bytes.BoxType {
  normal_box_type(b"cslg")
}

///|
/// `sdtp` のボックス種別。上流 `SdtpBox::TYPE` に対応する。
fn sdtp_type() -> @bytes.BoxType {
  normal_box_type(b"sdtp")
}

///|
/// `stsc` のボックス種別。上流 `StscBox::TYPE` に対応する。
fn stsc_type() -> @bytes.BoxType {
  normal_box_type(b"stsc")
}

///|
/// `stsz` のボックス種別。上流 `StszBox::TYPE` に対応する。
fn stsz_type() -> @bytes.BoxType {
  normal_box_type(b"stsz")
}

///|
/// `stco` のボックス種別。上流 `StcoBox::TYPE` に対応する。
fn stco_type() -> @bytes.BoxType {
  normal_box_type(b"stco")
}

///|
/// `co64` のボックス種別。上流 `Co64Box::TYPE` に対応する。
fn co64_type() -> @bytes.BoxType {
  normal_box_type(b"co64")
}

///|
/// `stss` のボックス種別。上流 `StssBox::TYPE` に対応する。
fn stss_type() -> @bytes.BoxType {
  normal_box_type(b"stss")
}

///|
/// `avc1` のボックス種別。上流 `Avc1Box::TYPE` に対応する。
fn avc1_type() -> @bytes.BoxType {
  normal_box_type(b"avc1")
}

///|
/// `avcC` のボックス種別。上流 `AvccBox::TYPE` に対応する。
fn avcc_type() -> @bytes.BoxType {
  normal_box_type(b"avcC")
}

///|
/// `hev1` のボックス種別。上流 `Hev1Box::TYPE` に対応する。
fn hev1_type() -> @bytes.BoxType {
  normal_box_type(b"hev1")
}

///|
/// `hvc1` のボックス種別。上流 `Hvc1Box::TYPE` に対応する。
fn hvc1_type() -> @bytes.BoxType {
  normal_box_type(b"hvc1")
}

///|
/// `hvcC` のボックス種別。上流 `HvccBox::TYPE` に対応する。
fn hvcc_type() -> @bytes.BoxType {
  normal_box_type(b"hvcC")
}

///|
/// `vp08` のボックス種別。上流 `Vp08Box::TYPE` に対応する。
fn vp08_type() -> @bytes.BoxType {
  normal_box_type(b"vp08")
}

///|
/// `vp09` のボックス種別。上流 `Vp09Box::TYPE` に対応する。
fn vp09_type() -> @bytes.BoxType {
  normal_box_type(b"vp09")
}

///|
/// `vpcC` のボックス種別。上流 `VpccBox::TYPE` に対応する。
fn vpcc_type() -> @bytes.BoxType {
  normal_box_type(b"vpcC")
}

///|
/// `av01` のボックス種別。上流 `Av01Box::TYPE` に対応する。
fn av01_type() -> @bytes.BoxType {
  normal_box_type(b"av01")
}

///|
/// `av1C` のボックス種別。上流 `Av1cBox::TYPE` に対応する。
fn av1c_type() -> @bytes.BoxType {
  normal_box_type(b"av1C")
}

///|
/// `Opus` のボックス種別。上流 `OpusBox::TYPE` に対応する。
fn opus_type() -> @bytes.BoxType {
  normal_box_type(b"Opus")
}

///|
/// `dOps` のボックス種別。上流 `DopsBox::TYPE` に対応する。
fn dops_type() -> @bytes.BoxType {
  normal_box_type(b"dOps")
}

///|
/// `mp4a` のボックス種別。上流 `Mp4aBox::TYPE` に対応する。
fn mp4a_type() -> @bytes.BoxType {
  normal_box_type(b"mp4a")
}

///|
/// `esds` のボックス種別。上流 `EsdsBox::TYPE` に対応する。
fn esds_type() -> @bytes.BoxType {
  normal_box_type(b"esds")
}

///|
/// `fLaC` のボックス種別。上流 `FlacBox::TYPE` に対応する。
fn flac_type() -> @bytes.BoxType {
  normal_box_type(b"fLaC")
}

///|
/// `dfLa` のボックス種別。上流 `DflaBox::TYPE` に対応する。
fn dfla_type() -> @bytes.BoxType {
  normal_box_type(b"dfLa")
}

///|
/// `mvex` のボックス種別。上流 `MvexBox::TYPE` に対応する。
fn mvex_type() -> @bytes.BoxType {
  normal_box_type(b"mvex")
}

///|
/// `mehd` のボックス種別。上流 `MehdBox::TYPE` に対応する。
fn mehd_type() -> @bytes.BoxType {
  normal_box_type(b"mehd")
}

///|
/// `trex` のボックス種別。上流 `TrexBox::TYPE` に対応する。
fn trex_type() -> @bytes.BoxType {
  normal_box_type(b"trex")
}

///|
/// `moof` のボックス種別。上流 `MoofBox::TYPE` に対応する。
fn moof_type() -> @bytes.BoxType {
  normal_box_type(b"moof")
}

///|
/// `mfhd` のボックス種別。上流 `MfhdBox::TYPE` に対応する。
fn mfhd_type() -> @bytes.BoxType {
  normal_box_type(b"mfhd")
}

///|
/// `traf` のボックス種別。上流 `TrafBox::TYPE` に対応する。
fn traf_type() -> @bytes.BoxType {
  normal_box_type(b"traf")
}

///|
/// `tfhd` のボックス種別。上流 `TfhdBox::TYPE` に対応する。
fn tfhd_type() -> @bytes.BoxType {
  normal_box_type(b"tfhd")
}

///|
/// `tfdt` のボックス種別。上流 `TfdtBox::TYPE` に対応する。
fn tfdt_type() -> @bytes.BoxType {
  normal_box_type(b"tfdt")
}

///|
/// `trun` のボックス種別。上流 `TrunBox::TYPE` に対応する。
fn trun_type() -> @bytes.BoxType {
  normal_box_type(b"trun")
}

///|
/// `sidx` のボックス種別。上流 `SidxBox::TYPE` に対応する。
fn sidx_type() -> @bytes.BoxType {
  normal_box_type(b"sidx")
}

///|
/// `mfra` のボックス種別。上流 `MfraBox::TYPE` に対応する。
fn mfra_type() -> @bytes.BoxType {
  normal_box_type(b"mfra")
}

///|
/// `tfra` のボックス種別。上流 `TfraBox::TYPE` に対応する。
fn tfra_type() -> @bytes.BoxType {
  normal_box_type(b"tfra")
}

///|
/// `mfro` のボックス種別。上流 `MfroBox::TYPE` に対応する。
fn mfro_type() -> @bytes.BoxType {
  normal_box_type(b"mfro")
}

///|
/// `tfra` の可変長整数を書く（1〜4 バイト、ビッグエンディアン）。
fn write_variable_uint(
  cursor : @bytes.WriteCursor,
  value : UInt32,
  byte_count : Int32,
) -> Unit raise @bytes.Mp4Error {
  if byte_count == 1 {
    cursor.write_u8(value)
  } else if byte_count == 2 {
    cursor.write_u16(value)
  } else if byte_count == 3 {
    cursor.write_u24(value)
  } else if byte_count == 4 {
    cursor.write_u32(value)
  } else {
    raise @bytes.Mp4Error::invalid_data(
      "Invalid byte count for variable uint: \{byte_count}",
    )
  }
}

///|
/// `tfra` の可変長整数を読む（1〜4 バイト、ビッグエンディアン）。
fn read_variable_uint(
  cursor : @bytes.ReadCursor,
  byte_count : Int32,
) -> UInt32 raise @bytes.Mp4Error {
  if byte_count == 1 {
    cursor.read_u8()
  } else if byte_count == 2 {
    cursor.read_u16()
  } else if byte_count == 3 {
    cursor.read_u24()
  } else if byte_count == 4 {
    cursor.read_u32()
  } else {
    raise @bytes.Mp4Error::invalid_data(
      "Invalid byte count for variable uint: \{byte_count}",
    )
  }
}

///|
/// `stpp` のボックス種別。
fn stpp_type() -> @bytes.BoxType {
  normal_box_type(b"stpp")
}

///|
/// `wvtt` のボックス種別。
fn wvtt_type() -> @bytes.BoxType {
  normal_box_type(b"wvtt")
}

///|
/// `vttC` のボックス種別。
fn vttc_type() -> @bytes.BoxType {
  normal_box_type(b"vttC")
}

///|
/// `tx3g` のボックス種別。
fn tx3g_type() -> @bytes.BoxType {
  normal_box_type(b"tx3g")
}

///|
/// `ftab` のボックス種別。
fn ftab_type() -> @bytes.BoxType {
  normal_box_type(b"ftab")
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
