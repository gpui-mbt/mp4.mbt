///|
/// ボックスの最小ヘッダー長（4 バイトのサイズ + 4 バイトの種別）。
pub const MIN_BOX_HEADER_SIZE : Int32 = 8

///|
/// ボックスの最大ヘッダー長（4 + 4 + 16 の uuid usertype + 8 の largesize）。
pub const MAX_BOX_HEADER_SIZE : Int32 = 4 + 4 + 16 + 8

///|
/// ボックスのサイズと種別を持つ共通ヘッダー。
///
/// エンコード時のフィールド順は上流 `mp4-rs` と同じ
/// `size`(4) | `type`(4) | `usertype`(16, uuid のとき) | `largesize`(8, `size==1` のとき)。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x08mdat")
///   let header : @box.BoxHeader = @bytes.decode_from(cursor)
///   inspect(header.box_size().get(), content="8")
///   inspect(header.box_type().to_string(), content="mdat")
///   inspect(header.external_size(), content="8")
/// }
/// ```
pub struct BoxHeader {
  box_type : @bytes.BoxType
  box_size : BoxSize
} derive(Eq, Hash, Debug)

///|
pub extend BoxHeader with Eq::{equal, not_equal}

///|
pub extend BoxHeader with Hash::{hash, hash_combine}

///|
pub extend BoxHeader with Debug::{to_repr}

///|
/// 種別とサイズからヘッダーを作る。
pub fn BoxHeader::new(
  box_type : @bytes.BoxType,
  box_size : BoxSize,
) -> BoxHeader {
  { box_type, box_size, }
}

///|
/// 「ファイル末尾まで」の可変長ボックスのヘッダーを作る。
pub fn BoxHeader::new_variable_size(box_type : @bytes.BoxType) -> BoxHeader {
  { box_type, box_size: BoxSize::variable_size(), }
}

///|
/// ボックス種別を返す。
pub fn BoxHeader::box_type(self : BoxHeader) -> @bytes.BoxType {
  self.box_type
}

///|
/// ボックスサイズを返す。
pub fn BoxHeader::box_size(self : BoxHeader) -> BoxSize {
  self.box_size
}

///|
/// エンコード時のヘッダーのバイト数を返す
/// （[`MIN_BOX_HEADER_SIZE`] から [`MAX_BOX_HEADER_SIZE`] の範囲）。
pub fn BoxHeader::external_size(self : BoxHeader) -> Int32 {
  self.box_size.external_size() + self.box_type.external_size()
}

///|
/// canonical な（最小幅の）size 形式へ変換したヘッダーを返す。
///
/// [`@bytes.Encode`] による再エンコードはデコード時の variant を保つ
/// （wire-preserving）のに対し、この変換は `largesize` をそのままの payload を
/// 持つ `size32` 形式へ畳める場合に畳む。詳細は [`BoxSize::to_canonical`] を参照。
pub fn BoxHeader::to_canonical(
  self : BoxHeader,
) -> BoxHeader raise @bytes.Mp4Error {
  {
    box_type: self.box_type,
    box_size: self.box_size.to_canonical(self.box_type),
  }
}

///|
/// ヘッダー本体を読み、検証済みのヘッダーとヘッダー長を返す。
///
/// 位置は成功時のみ前進する（失敗時は呼び出し側が巻き戻す）。
fn decode_box_header(
  cursor : @bytes.ReadCursor,
) -> (BoxHeader, Int32) raise @bytes.Mp4Error {
  let size32 = cursor.read_u32()
  let fourcc = cursor.read_fourcc()
  let box_type = if fourcc.as_bytes() == b"uuid" {
    @bytes.BoxType::Uuid(@bytes.Uuid::from_bytes(cursor.read_bytes(16)))
  } else {
    @bytes.BoxType::Normal(fourcc)
  }
  let box_size = if size32 == 1 {
    BoxSize::U64(cursor.read_u64())
  } else {
    BoxSize::U32(size32)
  }
  let header = { box_type, box_size, }
  let header_size = header.external_size()
  let size = box_size.get()
  // size==0（可変長）はここでは値として許容する。実際の区切りは
  // decode_header_and_payload（size==0 を末尾までと解釈）と、入れ子側の
  // 呼び出し（size==0 を拒否）が決める。
  if size != 0 && size < header_size.to_uint64() {
    raise @bytes.Mp4Error::invalid_input(
      "Too small box size: actual=\{size}, expected=\{header_size} or more",
    )
  }
  (header, header_size)
}

///|
/// ヘッダーと、そのボックスのペイロード（ヘッダー直後からボックス末尾まで）を返す。
///
/// `size==0`（[`BoxSize::variable_size`]）はバッファ末尾までをペイロードとして扱う。
/// ISO/IEC 14496-12 ではこれはファイル末尾のトップレベルボックスにのみ有効であり、
/// 入れ子での拒否は呼び出し側が行う（上流 `UnknownBox::decode` と同じ分担）。
///
/// `size==1` + `largesize==0`（[`BoxSize::large_variable_size`]）は可変長として
/// 扱わず、ヘッダー長未満のサイズとして [`@bytes.ErrorKind::InvalidData`] で拒否する。
///
/// 失敗した場合はカーソル位置を開始位置へ戻す。
pub fn BoxHeader::decode_header_and_payload(
  cursor : @bytes.ReadCursor,
) -> (BoxHeader, BytesView) raise @bytes.Mp4Error {
  let start = cursor.position()
  let start_offset = cursor.offset()
  errdefer cursor.rewind_to(start)
  let (header, header_size) = decode_box_header(cursor)
  let box_size = header.box_size.get()
  if header.box_size == BoxSize::variable_size() {
    // size==0（BoxSize::U32(0)）だけを可変長として扱う。U64(0) は下の下限検査に落ちる。
    (header, cursor.read_remaining_view())
  } else {
    if box_size < header_size.to_uint64() {
      raise @bytes.Mp4Error::invalid_data(
          "box size is smaller than header size",
        )
        .with_offset(start_offset)
        .with_box_type(header.box_type)
    }
    let payload_size = box_size - header_size.to_uint64()
    let remaining = cursor.remaining().to_uint64()
    if payload_size > remaining {
      let error = @bytes.Mp4Error::insufficient_buffer(
        box_size,
        remaining + header_size.to_uint64(),
      )
      raise error.with_offset(start_offset).with_box_type(header.box_type)
    }
    (
      header,
      cursor.read_bytes_view(
        @bytes.uint64_to_index(payload_size, "payload size"),
      ),
    )
  }
}

///|
pub impl @bytes.Decode for BoxHeader with fn decode(cursor : @bytes.ReadCursor) -> BoxHeader raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  let (header, _header_size) = decode_box_header(cursor)
  header
}

///|
pub extend BoxHeader with @bytes.Decode::{decode}

///|
pub impl @bytes.Encode for BoxHeader with fn encode(
  self : BoxHeader,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  match self.box_size {
    U32(size) => cursor.write_u32(size)
    U64(_) => cursor.write_u32(1)
  }
  match self.box_type {
    Normal(fourcc) => cursor.write_fourcc(fourcc)
    Uuid(uuid) => {
      cursor.write_bytes(b"uuid")
      cursor.write_bytes(uuid.as_bytes())
    }
  }
  match self.box_size {
    U32(_) => ()
    U64(size) => cursor.write_u64(size)
  }
}

///|
pub extend BoxHeader with @bytes.Encode::{encode}
