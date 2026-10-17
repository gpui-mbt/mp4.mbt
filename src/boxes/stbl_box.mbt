///|
/// [ISO/IEC 14496-12] SampleTableBox（`stbl`）(親: [`MinfBox`])。
///
/// サンプルエントリー・サンプル尺・チャンク配置などのサンプルテーブルをまとめる。
/// 上流 `StblBox` に対応する。
///
/// デコードでは各種別の最初の出現を採用し、2 個目以降は [`UnknownBox`] として
/// [`StblBox::unknown_boxes`] に保持する。`stco` と `co64` の両方が現れた場合は
/// どちらもデコードしたうえで `stco` を採用する（上流と同じ）。
///
/// ```mbt check
/// test {
///   let box = @boxes.StblBox::new(
///     @boxes.StsdBox::new([]),
///     @boxes.SttsBox::new([]),
///     None,
///     None,
///     @boxes.StscBox::new([]),
///     @boxes.StszBox::Variable(entry_sizes=[]),
///     @bytes.Either::A(@boxes.StcoBox::new([])),
///     None,
///     None,
///     [],
///   )
///   let decoded : @boxes.StblBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.stsd_box.entries.length(), content="0")
///   match decoded.stco_or_co64_box {
///     @bytes.Either::A(stco) => inspect(stco.chunk_offsets.length(), content="0")
///     @bytes.Either::B(_) => fail("stco が得られるはず")
///   }
/// }
/// ```
pub struct StblBox {
  /// サンプルエントリー（コーデック情報等）を保持する `stsd` ボックス
  stsd_box : StsdBox
  /// サンプル毎の尺（DTS 差分）を保持する `stts` ボックス
  stts_box : SttsBox
  /// composition time offset（CTS - DTS）を保持する `ctts` ボックス（省略可）
  ctts_box : CttsBox?
  /// composition と decode の時刻関係を要約した `cslg` ボックス（省略可）
  cslg_box : CslgBox?
  /// サンプルからチャンクへのマッピングを保持する `stsc` ボックス
  stsc_box : StscBox
  /// サンプルサイズを保持する `stsz` ボックス
  stsz_box : StszBox
  /// チャンクの絶対オフセットを保持する `stco`（32-bit）または `co64`（64-bit）ボックス
  stco_or_co64_box : @bytes.Either[StcoBox, Co64Box]
  /// 同期サンプル（キーフレーム）のサンプル番号列を保持する `stss` ボックス（省略可）
  stss_box : StssBox?
  /// サンプル間の依存関係を保持する `sdtp` ボックス（省略可）
  sdtp_box : SdtpBox?
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend StblBox with Eq::{equal, not_equal}

///|
pub extend StblBox with Hash::{hash, hash_combine}

///|
pub extend StblBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn StblBox::new(
  stsd_box : StsdBox,
  stts_box : SttsBox,
  ctts_box : CttsBox?,
  cslg_box : CslgBox?,
  stsc_box : StscBox,
  stsz_box : StszBox,
  stco_or_co64_box : @bytes.Either[StcoBox, Co64Box],
  stss_box : StssBox?,
  sdtp_box : SdtpBox?,
  unknown_boxes : Array[UnknownBox],
) -> StblBox {
  {
    stsd_box,
    stts_box,
    ctts_box,
    cslg_box,
    stsc_box,
    stsz_box,
    stco_or_co64_box,
    stss_box,
    sdtp_box,
    unknown_boxes,
  }
}

///|
/// `stbl` をデコードする。
///
/// `stsd` / `stts` / `stsc` / `stsz` と `stco' or 'co64` は必須で、無い場合は
/// [`@bytes.ErrorKind::InvalidData`]（`"Missing mandatory '...' box in 'stbl' box"`）
/// で失敗する（上流と同じ理由文字列）。
pub impl @bytes.Decode for StblBox with fn decode(cursor : @bytes.ReadCursor) -> StblBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(stbl_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(stbl_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let mut stsd_box : StsdBox? = None
    let mut stts_box : SttsBox? = None
    let mut ctts_box : CttsBox? = None
    let mut cslg_box : CslgBox? = None
    let mut stsc_box : StscBox? = None
    let mut stsz_box : StszBox? = None
    let mut stco_box : StcoBox? = None
    let mut co64_box : Co64Box? = None
    let mut stss_box : StssBox? = None
    let mut sdtp_box : SdtpBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == stsd_type() && stsd_box is None {
        stsd_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == stts_type() && stts_box is None {
        stts_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == ctts_type() && ctts_box is None {
        ctts_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == cslg_type() && cslg_box is None {
        cslg_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == stsc_type() && stsc_box is None {
        stsc_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == stsz_type() && stsz_box is None {
        stsz_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == stco_type() && stco_box is None {
        stco_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == co64_type() && co64_box is None {
        co64_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == stss_type() && stss_box is None {
        stss_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == sdtp_type() && sdtp_box is None {
        sdtp_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      stsd_box: check_mandatory_box(stsd_box, "stsd", "stbl"),
      stts_box: check_mandatory_box(stts_box, "stts", "stbl"),
      ctts_box,
      cslg_box,
      stsc_box: check_mandatory_box(stsc_box, "stsc", "stbl"),
      stsz_box: check_mandatory_box(stsz_box, "stsz", "stbl"),
      stco_or_co64_box: check_mandatory_box(
        match stco_box {
          Some(stco) => Some(@bytes.Either::A(stco))
          None =>
            match co64_box {
              Some(co64) => Some(@bytes.Either::B(co64))
              None => None
            }
        },
        "stco' or 'co64",
        "stbl",
      ),
      stss_box,
      sdtp_box,
      unknown_boxes,
    }
  })
}

///|
pub extend StblBox with @bytes.Decode::{decode}

///|
/// `stbl` を canonical な形式でエンコードする。
pub impl @bytes.Encode for StblBox with fn encode(
  self : StblBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, stbl_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.stsd_box, payload)
    @bytes.Encode::encode(self.stts_box, payload)
    match self.ctts_box {
      Some(ctts_box) => @bytes.Encode::encode(ctts_box, payload)
      None => ()
    }
    match self.cslg_box {
      Some(cslg_box) => @bytes.Encode::encode(cslg_box, payload)
      None => ()
    }
    @bytes.Encode::encode(self.stsc_box, payload)
    @bytes.Encode::encode(self.stsz_box, payload)
    match self.stco_or_co64_box {
      @bytes.Either::A(stco_box) => @bytes.Encode::encode(stco_box, payload)
      @bytes.Either::B(co64_box) => @bytes.Encode::encode(co64_box, payload)
    }
    match self.stss_box {
      Some(stss_box) => @bytes.Encode::encode(stss_box, payload)
      None => ()
    }
    match self.sdtp_box {
      Some(sdtp_box) => @bytes.Encode::encode(sdtp_box, payload)
      None => ()
    }
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend StblBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for StblBox with fn box_type(_self) {
  stbl_type()
}

///|
/// `stsd`、`stts`、`ctts`（あれば）、`cslg`（あれば）、`stsc`、`stsz`、
/// `stco` / `co64`、`stss`（あれば）、`sdtp`（あれば）、続いて未知ボックス
/// （ファイル順）を返す。
pub impl @box.BaseBox for StblBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  children.push(self.stsd_box)
  children.push(self.stts_box)
  match self.ctts_box {
    Some(ctts_box) => children.push(ctts_box)
    None => ()
  }
  match self.cslg_box {
    Some(cslg_box) => children.push(cslg_box)
    None => ()
  }
  children.push(self.stsc_box)
  children.push(self.stsz_box)
  children.push(self.stco_or_co64_box)
  match self.stss_box {
    Some(stss_box) => children.push(stss_box)
    None => ()
  }
  match self.sdtp_box {
    Some(sdtp_box) => children.push(sdtp_box)
    None => ()
  }
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend StblBox with @box.BaseBox::{box_type, is_unknown_box, children}
