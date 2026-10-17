// 複数の `moof`/`mdat` を持つ単一 fMP4 ファイルを incremental に読む demuxer。
//
// 内部で `Fmp4SegmentDemuxer` を再利用し、segment 側の相対 `data_offset` に
// `moof` のファイル位置を加算して絶対位置へ変換する。

///|
/// ファイル全体の読み進め方。
priv enum Fmp4Phase {
  ReadFtypBoxHeader
  ReadFtypBox(box_size~ : Int32)
  ReadMoovBoxHeader(offset~ : Int32)
  ReadMoovBox(offset~ : Int32, box_size~ : Int32)
  ReadTopLevelBoxHeader(offset~ : Int32)
  ReadMoofBox(offset~ : Int32, box_size~ : Int32)
  ReadMdatBoxHeader(moof_offset~ : Int32, mdat_offset~ : Int32)
  ReadMediaSegment(
    moof_offset~ : Int32,
    segment_size~ : Int32,
    next_offset~ : Int32
  )
  EndOfFile
}

///|
/// ファイル全体での sample entry 通知状態。
priv struct Fmp4TrackRuntime {
  /// 最後に `next_sample()` が返した sample entry
  mut sample_entry : @boxes.SampleEntry?
  /// 内部 segment demuxer が最後に返した sample entry
  mut inner_sample_entry : @boxes.SampleEntry?
}

///|
/// `next_sample()` に渡す保留サンプル。
priv struct Fmp4PendingSample {
  track_index : Int32
  timestamp : UInt64
  duration : UInt32
  keyframe : Bool
  data_offset : UInt64
  data_size : UInt32
  composition_time_offset : Int64?
  sample_entry : @boxes.SampleEntry?
}

///|
/// 完全な fMP4 ファイルを incremental にデマルチプレックスする構造体。
///
/// `required_input()` が要求する範囲を読み、`handle_input()` へ渡す。
/// `tracks()` で初期化後のトラック情報を取得し、`next_sample()` でサンプルを
/// 取り出す。取り出せるサンプルが残っている間は `handle_input()` を呼ばないこと。
pub struct Fmp4FileDemuxer {
  priv mut phase : Fmp4Phase
  priv inner : Fmp4SegmentDemuxer
  priv mut track_infos : Array[TrackInfo]
  priv mut track_runtimes : Array[Fmp4TrackRuntime]
  priv mut pending : Array[Fmp4PendingSample]
  priv mut pending_index : Int32
  priv mut handle_input_error : DemuxError?
}

///|
/// 新しい demuxer を作る。
pub fn Fmp4FileDemuxer::new() -> Fmp4FileDemuxer {
  {
    phase: ReadFtypBoxHeader,
    inner: Fmp4SegmentDemuxer::new(),
    track_infos: [],
    track_runtimes: [],
    pending: [],
    pending_index: 0,
    handle_input_error: None,
  }
}

///|
/// 現在必要な入力範囲を返す。
pub fn Fmp4FileDemuxer::required_input(
  self : Fmp4FileDemuxer,
) -> RequiredInput? {
  if self.handle_input_error is Some(_) ||
    self.pending_index < self.pending.length() {
    return None
  }
  match self.phase {
    ReadFtypBoxHeader =>
      Some(RequiredInput::{ position: 0UL, size: Some(32UL), })
    ReadFtypBox(box_size~) =>
      Some(RequiredInput::{ position: 0UL, size: Some(box_size.to_uint64()), })
    ReadMoovBoxHeader(offset~) =>
      Some(RequiredInput::{ position: offset.to_uint64(), size: Some(32UL), })
    ReadMoovBox(offset~, box_size~) =>
      Some(RequiredInput::{
        position: offset.to_uint64(),
        size: Some(box_size.to_uint64()),
      })
    ReadTopLevelBoxHeader(offset~) =>
      Some(RequiredInput::{ position: offset.to_uint64(), size: Some(32UL), })
    ReadMoofBox(offset~, box_size~) =>
      Some(RequiredInput::{
        position: offset.to_uint64(),
        size: Some(box_size.to_uint64()),
      })
    ReadMdatBoxHeader(mdat_offset~, ..) =>
      Some(RequiredInput::{
        position: mdat_offset.to_uint64(),
        size: Some(32UL),
      })
    ReadMediaSegment(moof_offset~, segment_size~, ..) =>
      Some(RequiredInput::{
        position: moof_offset.to_uint64(),
        size: Some(segment_size.to_uint64()),
      })
    EndOfFile => None
  }
}

///|
/// ファイルデータを入力として処理を進める。
pub fn Fmp4FileDemuxer::handle_input(
  self : Fmp4FileDemuxer,
  input : Input,
) -> Unit {
  if self.handle_input_error is None {
    match self.required_input() {
      Some(required) =>
        if input.slice_range(required.position, None) is None {
          let reason = "handle_input() error: expected input starting at position \{required.position}, but got \{input.data.length()} bytes starting at position \{input.position}"
          self.handle_input_error = Some(
            DemuxError::DecodeError(@bytes.Mp4Error::invalid_input(reason)),
          )
          return
        }
      None => ()
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
/// 初期化済みのトラック情報を返す。
pub fn Fmp4FileDemuxer::tracks(
  self : Fmp4FileDemuxer,
) -> Array[TrackInfo] raise DemuxError {
  match self.handle_input_error {
    Some(e) => {
      self.handle_input_error = None
      raise e
    }
    None => ()
  }
  if !self.is_initialized() {
    match self.required_input() {
      Some(required) => raise DemuxError::InputRequired(required)
      None => raise DemuxError::InvalidState("unexpected end of input")
    }
  }
  self.track_infos
}

///|
/// 次のサンプルを返す。ファイル終端では `None` を返す。
pub fn Fmp4FileDemuxer::next_sample(
  self : Fmp4FileDemuxer,
) -> Sample? raise DemuxError {
  match self.handle_input_error {
    Some(e) => {
      self.handle_input_error = None
      raise e
    }
    None => ()
  }
  if self.pending_index < self.pending.length() {
    let p = self.pending[self.pending_index]
    self.pending_index = self.pending_index + 1
    return Some(Sample::{
      track: self.track_infos[p.track_index],
      sample_entry: p.sample_entry,
      keyframe: p.keyframe,
      timestamp: p.timestamp,
      duration: p.duration,
      data_offset: p.data_offset,
      data_size: p.data_size,
      composition_time_offset: p.composition_time_offset,
    })
  }
  match self.phase {
    EndOfFile => None
    _ =>
      match self.required_input() {
        Some(required) => raise DemuxError::InputRequired(required)
        None => None
      }
  }
}

///|
/// 初期化済みかどうか。
fn Fmp4FileDemuxer::is_initialized(self : Fmp4FileDemuxer) -> Bool {
  match self.phase {
    ReadFtypBoxHeader
    | ReadFtypBox(..)
    | ReadMoovBoxHeader(..)
    | ReadMoovBox(..) => false
    _ => true
  }
}

///|
fn Fmp4FileDemuxer::handle_input_inner(
  self : Fmp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadFtypBoxHeader => self.read_ftyp_box_header(input)
    ReadFtypBox(..) => self.read_ftyp_box(input)
    ReadMoovBoxHeader(..) => self.read_moov_box_header(input)
    ReadMoovBox(..) => self.read_moov_box(input)
    ReadTopLevelBoxHeader(..) => self.read_top_level_box_header(input)
    ReadMoofBox(..) => self.read_moof_box(input)
    ReadMdatBoxHeader(..) => self.read_mdat_box_header(input)
    ReadMediaSegment(..) => self.read_media_segment(input)
    EndOfFile => ()
  }
}

///|
/// 入力から指定範囲を切り出す。不足なら `InputRequired` を返す。
fn Fmp4FileDemuxer::available(
  _self : Fmp4FileDemuxer,
  input : Input,
  position : Int32,
  size : Int32?,
) -> BytesView raise DemuxError {
  match
    input.slice_range(
      position.to_uint64(),
      size.map(fn(size) { size.to_uint64() }),
    ) {
    Some(view) => view
    None =>
      raise DemuxError::InputRequired(RequiredInput::{
        position: position.to_uint64(),
        size: size.map(fn(size) { size.to_uint64() }),
      })
  }
}

///|
/// 入力の末尾が指定位置以前かどうか。
fn Fmp4FileDemuxer::at_eof(
  _self : Fmp4FileDemuxer,
  input : Input,
  offset : Int32,
) -> Bool {
  input.position.to_int() + input.data.length() <= offset
}

///|
/// 指定位置のボックスヘッダーだけを読む（ペイロードは読まない）。
fn Fmp4FileDemuxer::peek_header(
  _self : Fmp4FileDemuxer,
  input : Input,
  offset : Int32,
) -> @box.BoxHeader raise DemuxError {
  let view = match input.slice_range(offset.to_uint64(), None) {
    Some(view) => view
    None =>
      raise DemuxError::InputRequired(RequiredInput::{
        position: offset.to_uint64(),
        size: Some(32UL),
      })
  }
  if view.length() < 8 {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data("incomplete top-level box header"),
    )
  }
  segment_wrap(fn() raise @bytes.Mp4Error {
    @bytes.decode_from(@bytes.ReadCursor::from_view(view, offset.to_uint64()))
  })
}

///|
/// ヘッダーが宣言したボックスサイズを `Int` で返す。
fn Fmp4FileDemuxer::declared_size(
  _self : Fmp4FileDemuxer,
  header : @box.BoxHeader,
) -> Int32 raise DemuxError {
  let size = header.box_size().get()
  if size > segment_max_int {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data("box size exceeds Int range"),
    )
  }
  size.to_int()
}

///|
fn Fmp4FileDemuxer::read_ftyp_box_header(
  self : Fmp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  let header = self.peek_header(input, 0)
  if header.box_type().as_bytes() != b"ftyp" {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data("ftyp box not found at the beginning"),
    )
  }
  if header.box_size().get() == 0UL {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data("ftyp box size must be non-zero"),
    )
  }
  let box_size = self.declared_size(header)
  self.phase = ReadFtypBox(box_size~)
}

///|
fn Fmp4FileDemuxer::read_ftyp_box(
  self : Fmp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadFtypBox(box_size~) => {
      let view = self.available(input, 0, Some(box_size))
      let _ftyp : @boxes.FtypBox = segment_wrap(fn() raise @bytes.Mp4Error {
        @bytes.decode_from(@bytes.ReadCursor::from_view(view, 0UL))
      })
      self.phase = ReadMoovBoxHeader(offset=box_size)
    }
    _ => abort("BUG")
  }
}

///|
fn Fmp4FileDemuxer::read_moov_box_header(
  self : Fmp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadMoovBoxHeader(offset~) => {
      let header = self.peek_header(input, offset)
      if header.box_size().get() == 0UL {
        raise DemuxError::DecodeError(
          @bytes.Mp4Error::invalid_data("moov box not found"),
        )
      }
      let box_size = if header.box_size().get() == 0UL {
        raise DemuxError::DecodeError(
          @bytes.Mp4Error::invalid_data("moov box not found"),
        )
      } else {
        self.declared_size(header)
      }
      if header.box_type().as_bytes() == b"moov" {
        self.phase = ReadMoovBox(offset~, box_size~)
      } else {
        self.phase = ReadMoovBoxHeader(offset=offset + box_size)
      }
    }
    _ => abort("BUG")
  }
}

///|
fn Fmp4FileDemuxer::read_moov_box(
  self : Fmp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadMoovBox(offset~, box_size~) => {
      let view = self.available(input, offset, Some(box_size))
      let moov_cursor = @bytes.ReadCursor::from_view(view, offset.to_uint64())
      let moov : @boxes.MoovBox = segment_wrap(fn() raise @bytes.Mp4Error {
        @bytes.decode_from(moov_cursor)
      })
      let track_infos : Array[TrackInfo] = []
      let track_runtimes : Array[Fmp4TrackRuntime] = []
      for trak in moov.trak_boxes {
        let kind = match trak.mdia_box.hdlr_box.track_kind() {
          Some(kind) => kind
          None => continue
        }
        track_infos.push(TrackInfo::{
          track_id: trak.tkhd_box.track_id,
          kind,
          duration: trak.mdia_box.mdhd_box.duration,
          timescale: trak.mdia_box.mdhd_box.timescale,
        })
        track_runtimes.push({ sample_entry: None, inner_sample_entry: None, })
      }
      self.inner.handle_init_segment_view(view)
      self.track_infos = track_infos
      self.track_runtimes = track_runtimes
      self.pending = []
      self.pending_index = 0
      self.phase = ReadTopLevelBoxHeader(offset=offset + box_size)
    }
    _ => abort("BUG")
  }
}

///|
fn Fmp4FileDemuxer::read_top_level_box_header(
  self : Fmp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadTopLevelBoxHeader(offset~) => {
      if self.at_eof(input, offset) {
        self.phase = EndOfFile
        return
      }
      let header = self.peek_header(input, offset)
      if header.box_size().get() == 0UL {
        self.phase = EndOfFile
        return
      }
      let box_size = self.declared_size(header)
      if header.box_type().as_bytes() == b"moof" {
        self.phase = ReadMoofBox(offset~, box_size~)
      } else {
        self.phase = ReadTopLevelBoxHeader(offset=offset + box_size)
      }
    }
    _ => abort("BUG")
  }
}

///|
fn Fmp4FileDemuxer::read_moof_box(
  self : Fmp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadMoofBox(offset~, box_size~) => {
      let view = self.available(input, offset, Some(box_size))
      let moof : @boxes.MoofBox = segment_wrap(fn() raise @bytes.Mp4Error {
        @bytes.decode_from(
          @bytes.ReadCursor::from_view(view, offset.to_uint64()),
        )
      })
      for traf in moof.traf_boxes {
        if traf.tfhd_box.base_data_offset is Some(_) {
          raise DemuxError::DecodeError(
            @bytes.Mp4Error::invalid_data(
              "tfhd with absolute base_data_offset is not supported in Fmp4FileDemuxer",
            ),
          )
        }
      }
      self.phase = ReadMdatBoxHeader(
        moof_offset=offset,
        mdat_offset=offset + box_size,
      )
    }
    _ => abort("BUG")
  }
}

///|
fn Fmp4FileDemuxer::read_mdat_box_header(
  self : Fmp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadMdatBoxHeader(moof_offset~, mdat_offset~) => {
      let header = self.peek_header(input, mdat_offset)
      if header.box_type().as_bytes() != b"mdat" {
        if header.box_type().as_bytes() == b"moof" {
          raise DemuxError::DecodeError(
            @bytes.Mp4Error::invalid_data("expected mdat box after moof"),
          )
        }
        if header.box_size().get() == 0UL {
          raise DemuxError::DecodeError(
            @bytes.Mp4Error::invalid_data(
              "found box with size=0 between moof and mdat",
            ),
          )
        }
        self.phase = ReadMdatBoxHeader(
          moof_offset~,
          mdat_offset=mdat_offset + self.declared_size(header),
        )
        return
      }
      let mdat_end = if header.box_size().get() == 0UL {
        input.position.to_int() + input.data.length()
      } else {
        mdat_offset + self.declared_size(header)
      }
      self.phase = ReadMediaSegment(
        moof_offset~,
        segment_size=mdat_end - moof_offset,
        next_offset=mdat_end,
      )
    }
    _ => abort("BUG")
  }
}

///|
fn Fmp4FileDemuxer::read_media_segment(
  self : Fmp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadMediaSegment(moof_offset~, segment_size~, next_offset~) => {
      let view = self.available(input, moof_offset, Some(segment_size))
      let samples = self.inner.handle_media_segment_view(
        view,
        allow_base_data_offset=false,
      )
      let pending : Array[Fmp4PendingSample] = []
      for sample in samples {
        let entry = match sample.sample_entry {
          Some(entry) => {
            self.track_runtimes[sample.track.track_id_index(self.track_infos)].inner_sample_entry
            = Some(entry)
            Some(entry)
          }
          None =>
            match
              self.track_runtimes[sample.track.track_id_index(self.track_infos)].inner_sample_entry {
              Some(entry) => Some(entry)
              None => None
            }
        }
        pending.push({
          track_index: sample.track.track_id_index(self.track_infos),
          timestamp: sample.timestamp,
          duration: sample.duration,
          keyframe: sample.keyframe,
          data_offset: sample.data_offset + moof_offset.to_uint64(),
          data_size: sample.data_size,
          composition_time_offset: sample.composition_time_offset,
          sample_entry: entry,
        })
      }
      pending.sort_by(fn(a, b) {
        if a.timestamp < b.timestamp {
          -1
        } else if a.timestamp > b.timestamp {
          1
        } else if a.track_index < b.track_index {
          -1
        } else if a.track_index > b.track_index {
          1
        } else if a.data_offset < b.data_offset {
          -1
        } else if a.data_offset > b.data_offset {
          1
        } else {
          0
        }
      })
      // ファイル全体の取り出し順で sample entry の変更通知を決める。
      let finalized : Array[Fmp4PendingSample] = []
      for p in pending {
        let emit = self.track_runtimes[p.track_index].sample_entry !=
          p.sample_entry
        finalized.push({
          track_index: p.track_index,
          timestamp: p.timestamp,
          duration: p.duration,
          keyframe: p.keyframe,
          data_offset: p.data_offset,
          data_size: p.data_size,
          composition_time_offset: p.composition_time_offset,
          sample_entry: if emit {
            p.sample_entry
          } else {
            None
          },
        })
        if emit {
          self.track_runtimes[p.track_index].sample_entry = p.sample_entry
        }
      }
      self.pending = finalized
      self.pending_index = 0
      self.phase = ReadTopLevelBoxHeader(offset=next_offset)
    }
    _ => abort("BUG")
  }
}

///|
/// `TrackInfo` の配列から track_id の index を返す。
fn TrackInfo::track_id_index(
  self : TrackInfo,
  track_infos : Array[TrackInfo],
) -> Int32 {
  let mut index = 0
  while index < track_infos.length() {
    if track_infos[index].track_id == self.track_id {
      return index
    }
    index = index + 1
  }
  abort("BUG: track_id is not registered")
}
