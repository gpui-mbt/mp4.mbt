///|
/// MP4 ファイルの種別。
///
/// 上流 `Mp4FileKind` に対応する。
pub(all) enum Mp4FileKind {
  /// 通常の MP4 ファイル
  Mp4
  /// Fragmented MP4 ファイル
  FragmentedMp4
} derive(Eq, Hash, Debug)

///|
pub extend Mp4FileKind with Eq::{equal, not_equal}

///|
pub extend Mp4FileKind with Hash::{hash, hash_combine}

///|
pub extend Mp4FileKind with Debug::{to_repr}

///|
/// 上流 `BoxHeader::MAX_SIZE`（32 バイト）に対応する。
/// ボックスヘッダーとして取り得る最大サイズ。
let box_header_max_size : UInt64 = 32

///|
/// 上流の `usize::try_from` チェックに対応する、格納可能なサイズの上限。
///
/// Rust 側（64bit）では `usize::MAX` と実質 `u64::MAX` だが、MoonBit では
/// バッファ長が `Int` で表現されるため `Int` の最大値を上限とする。
let max_usable_size : UInt64 = 2147483647

///|
/// 4 バイトの FourCC を持つ通常ボックス種別を作る。
///
/// [`@bytes.FourCC::from_bytes`] は長さを検査するため失敗し得るが、ここへ渡すのは
/// 定数の 4 バイトのみなので失敗しない。
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
/// `moov` のボックス種別。上流の `MoovBox::TYPE` に対応する。
fn moov_type() -> @bytes.BoxType {
  normal_box_type(b"moov")
}

///|
/// `mvex` のボックス種別。
fn mvex_type() -> @bytes.BoxType {
  normal_box_type(b"mvex")
}

///|
/// 上流の `From<Error> for DemuxError` 変換に対応する、
/// デコード失敗を [`DemuxError::DecodeError`] に包むヘルパー。
fn[T] wrap_decode(f : () -> T raise @bytes.Mp4Error) -> T raise DemuxError {
  try f() catch {
    e => raise DemuxError::DecodeError(e)
  } noraise {
    v => v
  }
}

///|
/// MP4 ファイルか fragmented MP4 ファイルかを判定するための構造体。
///
/// 上流 `Mp4FileKindDetector` に対応する。判定は `moov` ボックス内に
/// `mvex` ボックスが存在するかどうかでのみ行い、ファイルの拡張子や
/// `ftyp` のブランドには依存しない。
///
/// 必要なデータは [`Mp4FileKindDetector::required_input`] で要求範囲として
/// 通知され、利用側はその範囲のデータを
/// [`Mp4FileKindDetector::handle_input`] で提供する。判定に不要な
/// ペイロード（例: 巨大な `mdat` ボックス）は読み込まないため、
/// `moov` が末尾近くにある non-faststart なファイルでも効率よく判定できる。
///
/// # Examples
///
/// ```mbt check
/// test {
///   let detector = @demux.Mp4FileKindDetector::new()
///   // 最初に要求されるのは先頭のボックスヘッダー分の 32 バイト
///   let required = detector.required_input().unwrap()
///   assert_eq(required.position, 0)
///   assert_eq(required.size, Some(32))
/// }
/// ```
pub struct Mp4FileKindDetector {
  priv mut phase : Phase
  priv mut handle_input_error : DemuxError?
}

///|
/// 上流の非公開 enum `Phase` に対応する。
priv enum Phase {
  ReadFtypBoxHeader
  ReadFtypBox(box_size~ : UInt64)
  ReadTopLevelBoxHeader(offset~ : UInt64)
  ReadMoovBox(offset~ : UInt64, box_size~ : UInt64?)
  Detected(kind~ : Mp4FileKind)
}

///|
/// `Mp4FileKindDetector` の新しいインスタンスを生成する。
pub fn Mp4FileKindDetector::new() -> Mp4FileKindDetector {
  { phase: ReadFtypBoxHeader, handle_input_error: None, }
}

///|
/// 現在必要な入力データの範囲を返す。
///
/// 上流 `Mp4FileKindDetector::required_input` に対応する。
/// 終端状態（判定済み、または回復不能な入力エラーの保持中）では
/// `None` を返す。
pub fn Mp4FileKindDetector::required_input(
  self : Mp4FileKindDetector,
) -> RequiredInput? {
  if self.handle_input_error is Some(_) {
    // エラーが発生した後は、これ以上のデータ要求は行わない
    return None
  }
  match self.phase {
    ReadFtypBoxHeader =>
      Some(RequiredInput::{ position: 0, size: Some(box_header_max_size), })
    ReadFtypBox(box_size~) =>
      Some(RequiredInput::{ position: 0, size: Some(box_size), })
    ReadTopLevelBoxHeader(offset~) =>
      Some(RequiredInput::{ position: offset, size: Some(box_header_max_size), })
    ReadMoovBox(offset~, box_size~) =>
      Some(RequiredInput::{ position: offset, size: box_size, })
    Detected(..) => None
  }
}

///|
/// 判定結果を返す。
///
/// 上流 `Mp4FileKindDetector::file_kind` に対応する。判定が完了していれば
/// `Some` を返し、まだ入力データが足りない場合は `None` を返す。
/// これまでの入力処理で回復不能なエラーが発生していた場合はそのエラーを
/// raise する。
pub fn Mp4FileKindDetector::file_kind(
  self : Mp4FileKindDetector,
) -> Mp4FileKind? raise DemuxError {
  match self.handle_input_error {
    Some(e) => raise e
    None =>
      match self.phase {
        Detected(kind~) => Some(kind)
        _ => None
      }
  }
}

///|
/// 入力データを処理する。
///
/// 上流 `Mp4FileKindDetector::handle_input` に対応する。
/// 入力データは必ずしも要求された範囲と一致している必要はないが、少なくとも
/// その要求範囲を含んでいる必要がある（例外として、要求位置から始まる短い
/// データは「ファイルがその位置で終わった」ものとして受理され、個別の
/// エラーとして報告される）。
///
/// 要求に適合しないデータが渡された場合は、以降の
/// [`Mp4FileKindDetector::file_kind`] は同じエラーを返し続ける。
pub fn Mp4FileKindDetector::handle_input(
  self : Mp4FileKindDetector,
  input : Input,
) -> Unit {
  if self.handle_input_error is None {
    match self.required_input() {
      Some(required) if !input_is_acceptable(required, input) => {
        let size_desc = match required.size {
          Some(size) => "at least \{size} bytes"
          None => "data up to EOF"
        }
        let reason = "handle_input() error: provided input does not contain the required data (expected \{size_desc} starting at position \{required.position}, but got \{input.data.length()} bytes starting at position \{input.position})"
        self.handle_input_error = Some(
          DemuxError::DecodeError(@bytes.Mp4Error::invalid_input(reason)),
        )
        return
      }
      _ => ()
    }
  }
  try self.handle_input_inner(input) catch {
    e =>
      match e {
        InputRequired(_) => ()
        _ => self.handle_input_error = Some(e)
      }
  } noraise {
    _ => ()
  }
}

///|
/// 上流 `Mp4FileKindDetector::handle_input_inner` に対応する。
fn Mp4FileKindDetector::handle_input_inner(
  self : Mp4FileKindDetector,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadFtypBoxHeader => self.read_ftyp_box_header(input)
    ReadFtypBox(..) => self.read_ftyp_box(input)
    ReadTopLevelBoxHeader(..) => self.read_top_level_box_header(input)
    ReadMoovBox(..) => self.read_moov_box(input)
    Detected(..) => ()
  }
}

///|
/// 上流 `Mp4FileKindDetector::input_is_acceptable` に対応する。
fn input_is_acceptable(required : RequiredInput, input : Input) -> Bool {
  required.is_satisfied_by(input) ||
  (
    input.position == required.position &&
    (match required.size {
      Some(size) => input.data.length().to_uint64() < size
      None => false
    })
  )
}

///|
/// 上流 `Mp4FileKindDetector::read_ftyp_box_header` に対応する。
fn Mp4FileKindDetector::read_ftyp_box_header(
  self : Mp4FileKindDetector,
  input : Input,
) -> Unit raise DemuxError {
  let data = available_bytes(input, 0, Some(box_header_max_size))
  let header : @box.BoxHeader = wrap_decode(() => {
    @bytes.decode_from(@bytes.ReadCursor::from_view(data, 0))
  })
  wrap_decode(() => header.box_type().expect(ftyp_type()))
  let box_size = header.box_size().get()
  if box_size > max_usable_size {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data("ftyp box size exceeds usize::MAX"),
    )
  }
  if box_size == 0 {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data("ftyp box size must be non-zero"),
    )
  }
  self.phase = ReadFtypBox(box_size~)
}

///|
/// 上流 `Mp4FileKindDetector::read_ftyp_box` に対応する。
fn Mp4FileKindDetector::read_ftyp_box(
  self : Mp4FileKindDetector,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadFtypBox(box_size~) => {
      let data = available_bytes(input, 0, Some(box_size))
      let cursor = @bytes.ReadCursor::from_view(
        match data.get_view(end=box_size.to_int()) {
          Some(view) => view
          None => data
        },
        0,
      )
      let _ : @boxes.FtypBox = wrap_decode(() => @bytes.decode_from(cursor))
      self.phase = ReadTopLevelBoxHeader(offset=cursor.offset())
    }
    _ => abort("BUG")
  }
}

///|
/// 上流 `Mp4FileKindDetector::read_top_level_box_header` に対応する。
fn Mp4FileKindDetector::read_top_level_box_header(
  self : Mp4FileKindDetector,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadTopLevelBoxHeader(offset~) => {
      if input.position == offset && input.data.is_empty() {
        raise DemuxError::DecodeError(
          @bytes.Mp4Error::invalid_data("moov box not found before EOF"),
        )
      }
      let data = available_bytes(input, offset, Some(box_header_max_size))
      let header : @box.BoxHeader = wrap_decode(() => {
        @bytes.decode_from(@bytes.ReadCursor::from_view(data, 0))
      })
      if header.box_type() == moov_type() {
        let box_size = header.box_size().get()
        if box_size == 0 {
          // サイズ 0 の場合は、データをファイルの終端まで取得する
          self.phase = ReadMoovBox(offset~, box_size=None)
        } else {
          if box_size > max_usable_size {
            raise DemuxError::DecodeError(
              @bytes.Mp4Error::invalid_data("moov box size exceeds usize::MAX"),
            )
          }
          self.phase = ReadMoovBox(offset~, box_size=Some(box_size))
        }
      } else {
        let box_size = header.box_size().get()
        if box_size == 0 {
          raise DemuxError::DecodeError(
            @bytes.Mp4Error::invalid_data(
              "top-level box with size=0 before moov is not supported",
            ),
          )
        }
        // `moov` ボックス以外のペイロードは読み込まず、次のボックスヘッダーへ進む
        if box_size > 0xFFFF_FFFF_FFFF_FFFFUL - offset {
          raise DemuxError::DecodeError(
            @bytes.Mp4Error::invalid_data("box offset overflow"),
          )
        }
        let next_offset = offset + box_size
        self.phase = ReadTopLevelBoxHeader(offset=next_offset)
      }
    }
    _ => abort("BUG")
  }
}

///|
/// 上流 `Mp4FileKindDetector::read_moov_box` に対応する。
fn Mp4FileKindDetector::read_moov_box(
  self : Mp4FileKindDetector,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadMoovBox(offset~, box_size~) => {
      let data = available_bytes(input, offset, box_size)
      let decode_input = match box_size {
        Some(box_size) =>
          match data.get_view(end=box_size.to_int()) {
            Some(view) => view
            None => data
          }
        None => data
      }
      let moov_box : @boxes.MoovBox = wrap_decode(() => {
        @bytes.decode_from(@bytes.ReadCursor::from_view(decode_input, 0))
      })

      // moov ボックス内に mvex ボックスがあるかどうかで判定する。
      // 現行の `MoovBox` では `mvex` は未型付けで `unknown_boxes` に保持される
      // （issue 0017 で型付けされる予定）
      let mut has_mvex = false
      for b in moov_box.unknown_boxes {
        if b.box_type == mvex_type() {
          has_mvex = true
        }
      }
      let kind = if has_mvex { FragmentedMp4 } else { Mp4 }
      self.phase = Detected(kind~)
    }
    _ => abort("BUG")
  }
}

///|
/// 入力データの中から指定された位置以降のバイト列を取得し、
/// `required_size` を満たしているか確認する。
///
/// 上流 `Mp4FileKindDetector::available_bytes` に対応する。
fn available_bytes(
  input : Input,
  position : UInt64,
  required_size : UInt64?,
) -> BytesView raise DemuxError {
  let data = match input.slice_range(position, None) {
    Some(data) => data
    None =>
      raise DemuxError::InputRequired(RequiredInput::{
        position,
        size: required_size,
      })
  }
  match required_size {
    Some(required_size) if data.length().to_uint64() < required_size =>
      if input.position == position {
        raise DemuxError::DecodeError(
          @bytes.Mp4Error::invalid_data(
            "input ended before the required range was available",
          ),
        )
      } else {
        raise DemuxError::InputRequired(RequiredInput::{
          position,
          size: Some(required_size),
        })
      }
    _ => data
  }
}
