///|
/// MP4 ファイル内のメディアトラックの情報。
///
/// 上流 `TrackInfo` に対応する。
pub(all) struct TrackInfo {
  /// トラック ID
  track_id : UInt32
  /// トラックの種類
  kind : @bytes.TrackKind
  /// トラックの尺（タイムスケール単位）
  ///
  /// 秒単位の尺は、この値を `timescale` で割ることで求められる。
  ///
  /// fMP4 の場合は init segment 由来の値であり、実際には 0 になることが多い。
  /// その場合は「未確定ないし実質不明相当」とみなしてよい。
  duration : UInt64
  /// トラックで使用されているタイムスケール
  timescale : @bytes.NonZeroU32
} derive(Eq, Hash, Debug)

///|
pub extend TrackInfo with Eq::{equal, not_equal}

///|
pub extend TrackInfo with Hash::{hash, hash_combine}

///|
pub extend TrackInfo with Debug::{to_repr}

///|
/// シーク位置を表す時間。
///
/// 上流 `core::time::Duration` に対応する。`nanos` は 1 秒未満の部分であり、
/// `0 <= nanos < 1_000_000_000` を満たす値だけが構築できる。
pub struct Duration {
  priv secs : UInt64
  priv nanos : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend Duration with Eq::{equal, not_equal}

///|
pub extend Duration with Hash::{hash, hash_combine}

///|
pub extend Duration with Debug::{to_repr}

///|
/// 1 秒をナノ秒で表した定数。
let nanos_per_sec : UInt64 = 1000000000

///|
/// 秒とナノ秒から [`Duration`] を構築する。
///
/// `nanos >= 1_000_000_000` の場合は `None` を返す
/// （上流 `Duration` ではそのような値を表現できない）。
pub fn Duration::new(secs : UInt64, nanos : UInt32) -> Duration? {
  if nanos.to_uint64() >= nanos_per_sec {
    None
  } else {
    Some({ secs, nanos, })
  }
}

///|
/// 秒から [`Duration`] を構築する。上流 `Duration::from_secs` に対応する。
pub fn Duration::from_secs(secs : UInt64) -> Duration {
  { secs, nanos: 0U, }
}

///|
/// ミリ秒から [`Duration`] を構築する。上流 `Duration::from_millis` に対応する。
pub fn Duration::from_millis(millis : UInt64) -> Duration {
  { secs: millis / 1000, nanos: (millis % 1000 * 1000000).to_uint(), }
}

///|
/// 秒部分を返す。上流 `Duration::as_secs` に対応する。
pub fn Duration::as_secs(self : Duration) -> UInt64 {
  self.secs
}

///|
/// 1 秒未満のナノ秒部分を返す。上流 `Duration::subsec_nanos` に対応する。
pub fn Duration::subsec_nanos(self : Duration) -> UInt32 {
  self.nanos
}

///|
/// デマルチプレックス処理で抽出されたメディアサンプル。
///
/// 上流 `Sample<'a>` に対応する。上流では `track` と `sample_entry` は
/// デマルチプレクサ内部への参照だが、MoonBit 側では値として保持する
/// （`TrackInfo` は不変値、`SampleEntry` はデコード済みの共有値）。
pub(all) struct Sample {
  /// サンプルが属するトラックの情報
  track : TrackInfo
  /// サンプルの詳細情報
  ///
  /// 前のサンプルから変更がない場合には `None` になる
  /// （最初のサンプルは常に `Some` となる）
  sample_entry : @boxes.SampleEntry?
  /// キーフレームであるかの判定
  keyframe : Bool
  /// サンプルのタイムスタンプ（トラックのタイムスケール単位）
  ///
  /// この値は「同じトラック内の前方に位置するサンプルの尺の累積値」であり、
  /// decode timestamp を表す。PTS は `timestamp + composition_time_offset` で
  /// 計算できる。
  timestamp : UInt64
  /// サンプルの尺（トラックのタイムスケール単位）
  duration : UInt32
  /// 入力データ内におけるサンプルデータの開始位置（バイト単位）
  ///
  /// file demuxer ではファイル先頭からの絶対位置を表す。
  data_offset : UInt64
  /// サンプルデータのサイズ（バイト単位）
  data_size : UInt32
  /// コンポジション時間オフセット（トラックのタイムスケール単位）
  ///
  /// `ctts` ボックスが存在する場合に設定される。
  /// `ctts` ボックスがない場合は `None` となる。
  composition_time_offset : Int64?
} derive(Debug)

///|
pub extend Sample with Debug::{to_repr}

///|
/// 上流の非公開 enum `Phase`（`Mp4FileDemuxer` 用）に対応する。
priv enum DemuxPhase {
  ReadFtypBoxHeader
  ReadFtypBox(box_size~ : UInt64?)
  ReadMoovBoxHeader(offset~ : UInt64)
  ReadMoovBox(offset~ : UInt64, box_size~ : UInt64?)
  Initialized
}

///|
/// 上流の非公開 `TrackState` に対応する。
priv struct TrackState {
  table : @boxes.SampleTableAccessor
  timescale : @bytes.NonZeroU32
  mut next_sample_index : @bytes.NonZeroU32
}

///|
/// MP4 ファイルをデマルチプレックスしてメディアサンプルを取得する構造体。
///
/// 上流 `Mp4FileDemuxer` に対応する。`ftyp` と `moov` を読んで初期化し、
/// 全トラックから decode timestamp の時系列順にサンプルメタデータを返す。
///
/// この構造体自体は I/O 操作を行わない。必要なデータは
/// [`Mp4FileDemuxer::required_input`] で要求範囲として通知され、利用側は
/// その範囲のデータを [`Mp4FileDemuxer::handle_input`] で提供する。
/// サンプルデータそのもの（`mdat` ペイロード）は要求されないため、
/// `moov` が末尾にある巨大なファイルでも効率よく処理できる。
///
/// なお、ストリーミング用途での使用は想定していない。
///
/// # Examples
///
/// ```mbt check
/// test {
///   let demuxer = @demux.Mp4FileDemuxer::new()
///   // 最初に要求されるのは先頭のボックスヘッダー分の 32 バイト
///   let required = demuxer.required_input().unwrap()
///   assert_eq(required.position, 0)
///   assert_eq(required.size, Some(32))
/// }
/// ```
pub struct Mp4FileDemuxer {
  priv mut phase : DemuxPhase
  priv track_infos : Array[TrackInfo]
  priv tracks : Array[TrackState]
  priv mut handle_input_error : DemuxError?
}

///|
/// [`Mp4FileDemuxer`] の新しいインスタンスを生成する。
pub fn Mp4FileDemuxer::new() -> Mp4FileDemuxer {
  {
    phase: ReadFtypBoxHeader,
    track_infos: [],
    tracks: [],
    handle_input_error: None,
  }
}

///|
/// 次の処理を進めるために必要な I/O の位置とサイズを返す。
///
/// 上流 `Mp4FileDemuxer::required_input` に対応する。
/// デマルチプレックス処理が初期化済みの場合は `None` を返す。
pub fn Mp4FileDemuxer::required_input(self : Mp4FileDemuxer) -> RequiredInput? {
  if self.handle_input_error is Some(_) {
    return None
  }
  match self.phase {
    ReadFtypBoxHeader =>
      Some(RequiredInput::{ position: 0, size: Some(box_header_max_size), })
    ReadFtypBox(box_size~) =>
      Some(RequiredInput::{ position: 0, size: box_size, })
    ReadMoovBoxHeader(offset~) =>
      Some(RequiredInput::{ position: offset, size: Some(box_header_max_size), })
    ReadMoovBox(offset~, box_size~) =>
      Some(RequiredInput::{ position: offset, size: box_size, })
    Initialized => None
  }
}

///|
/// ファイルデータを入力として受け取り、デマルチプレックス処理を進める。
///
/// 上流 `Mp4FileDemuxer::handle_input` に対応する。
/// `input` には [`Mp4FileDemuxer::required_input`] が指定した範囲を包含する
/// データを一度に全て渡す必要がある（部分消費は行わない）。
///
/// 要求を満たさない入力が渡された場合はデマルチプレクサはエラー状態になり、
/// 以降 [`Mp4FileDemuxer::tracks`] や [`Mp4FileDemuxer::next_sample`] は
/// エラーを返す。要求範囲よりも多くのデータを渡す分には問題はない
/// （入力ファイル全体を一度に渡してもよい）。
pub fn Mp4FileDemuxer::handle_input(
  self : Mp4FileDemuxer,
  input : Input,
) -> Unit {
  if self.handle_input_error is None {
    match self.required_input() {
      Some(required) if !required.is_satisfied_by(input) => {
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
/// 上流 `Mp4FileDemuxer::handle_input_inner` に対応する。
///
/// 上流では各 phase 処理の末尾で自身を再帰的に呼び出し、入力データが続く
/// 限り複数の phase を一度に進める。
fn Mp4FileDemuxer::handle_input_inner(
  self : Mp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadFtypBoxHeader => self.read_ftyp_box_header(input)
    ReadFtypBox(..) => self.read_ftyp_box(input)
    ReadMoovBoxHeader(..) => self.read_moov_box_header(input)
    ReadMoovBox(..) => self.read_moov_box(input)
    Initialized => ()
  }
}

///|
/// 上流 `Mp4FileDemuxer::read_ftyp_box_header` に対応する。
fn Mp4FileDemuxer::read_ftyp_box_header(
  self : Mp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  let data = match input.slice_range(0, Some(box_header_max_size)) {
    Some(data) => data
    None => raise DemuxError::input_required(0, Some(box_header_max_size))
  }
  let header : @box.BoxHeader = wrap_decode(() => {
    @bytes.decode_from(@bytes.ReadCursor::from_view(data, 0))
  })
  wrap_decode(() => header.box_type().expect(ftyp_type()))
  // 合法な ftyp が usize::MAX を超えることは現実的にはないが、
  // 破損入力への防御として検査する（size 0 はファイル末尾までを意味する）
  let box_size = match header.box_size().get() {
    0 => None
    box_size => {
      if box_size > max_usable_size {
        raise DemuxError::DecodeError(
          @bytes.Mp4Error::invalid_data("ftyp box size exceeds usize::MAX"),
        )
      }
      Some(box_size)
    }
  }
  self.phase = ReadFtypBox(box_size~)
  self.handle_input_inner(input)
}

///|
/// 上流 `Mp4FileDemuxer::read_ftyp_box` に対応する。
fn Mp4FileDemuxer::read_ftyp_box(
  self : Mp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadFtypBox(box_size~) => {
      let data = match input.slice_range(0, box_size) {
        Some(data) => data
        None => raise DemuxError::input_required(0, box_size)
      }
      let cursor = @bytes.ReadCursor::from_view(data, 0)
      let _ftyp_box : @boxes.FtypBox = wrap_decode(() => {
        @bytes.decode_from(cursor)
      })
      self.phase = ReadMoovBoxHeader(offset=cursor.offset())
      self.handle_input_inner(input)
    }
    _ => abort("BUG")
  }
}

///|
/// 上流 `Mp4FileDemuxer::read_moov_box_header` に対応する。
fn Mp4FileDemuxer::read_moov_box_header(
  self : Mp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadMoovBoxHeader(offset~) => {
      let data = match input.slice_range(offset, Some(box_header_max_size)) {
        Some(data) => data
        None =>
          raise DemuxError::input_required(offset, Some(box_header_max_size))
      }
      let header : @box.BoxHeader = wrap_decode(() => {
        @bytes.decode_from(@bytes.ReadCursor::from_view(data, 0))
      })
      let box_size = match header.box_size().get() {
        0 => None
        box_size => Some(box_size)
      }
      if header.box_type() == moov_type() {
        let box_size = match box_size {
          Some(box_size) => {
            if box_size > max_usable_size {
              raise DemuxError::DecodeError(
                @bytes.Mp4Error::invalid_data(
                  "moov box size exceeds usize::MAX",
                ),
              )
            }
            Some(box_size)
          }
          None => None
        }
        self.phase = ReadMoovBox(offset~, box_size~)
      } else {
        match box_size {
          None =>
            raise DemuxError::DecodeError(
              @bytes.Mp4Error::invalid_data("moov box not found"),
            )
          Some(box_size) => {
            // 破損データで box_size が極端に大きい場合の加算オーバーフローを防ぐ
            if box_size > 0xFFFF_FFFF_FFFF_FFFFUL - offset {
              raise DemuxError::DecodeError(
                @bytes.Mp4Error::invalid_data("box offset overflow"),
              )
            }
            self.phase = ReadMoovBoxHeader(offset=offset + box_size)
          }
        }
      }
      self.handle_input_inner(input)
    }
    _ => abort("BUG")
  }
}

///|
/// 上流 `Mp4FileDemuxer::read_moov_box` に対応する。
fn Mp4FileDemuxer::read_moov_box(
  self : Mp4FileDemuxer,
  input : Input,
) -> Unit raise DemuxError {
  match self.phase {
    ReadMoovBox(offset~, box_size~) => {
      let data = match input.slice_range(offset, box_size) {
        Some(data) => data
        None => raise DemuxError::input_required(offset, box_size)
      }
      let moov_box : @boxes.MoovBox = wrap_decode(() => {
        @bytes.decode_from(@bytes.ReadCursor::from_view(data, 0))
      })
      for trak_box in moov_box.trak_boxes {
        // 上流と同じく `vide` / `soun` / `subt` / `text` 以外のハンドラー種別を
        // 持つトラックは読み飛ばす
        let kind = match trak_box.mdia_box.hdlr_box.track_kind() {
          Some(kind) => kind
          None => continue
        }
        let timescale = trak_box.mdia_box.mdhd_box.timescale
        let table = wrap_sample_table(() => {
          @boxes.SampleTableAccessor::new(trak_box.mdia_box.minf_box.stbl_box)
        })
        self.track_infos.push({
          track_id: trak_box.tkhd_box.track_id,
          kind,
          duration: trak_box.mdia_box.mdhd_box.duration,
          timescale,
        })
        self.tracks.push({
          table,
          timescale,
          next_sample_index: @bytes.NonZeroU32::one(),
        })
      }
      self.phase = Initialized
    }
    _ => abort("BUG")
  }
}

///|
/// MP4 ファイル内のすべてのメディアトラック情報を返す。
///
/// 上流 `Mp4FileDemuxer::tracks` に対応する。
/// I/O が必要な場合は [`DemuxError::InputRequired`] を raise する。
pub fn Mp4FileDemuxer::tracks(
  self : Mp4FileDemuxer,
) -> ArrayView[TrackInfo] raise DemuxError {
  self.ensure_initialized()
  self.track_infos[:]
}

///|
/// 時系列順に次のサンプルを取得する。
///
/// 上流 `Mp4FileDemuxer::next_sample` に対応する。
/// 全トラックの中でまだ取得していないサンプルのうち、最も早い
/// タイムスタンプを持つものを返す。サンプルが存在しない場合は `None`。
/// タイムスタンプの比較は上流と同じく `Duration::from_secs(timestamp) /
/// timescale` で行い（浮動小数を経由しない）、同一時刻では
/// トラック走査順で先のものが選ばれる。
pub fn Mp4FileDemuxer::next_sample(
  self : Mp4FileDemuxer,
) -> Sample? raise DemuxError {
  self.ensure_initialized()

  // 全トラックの中で最も早いタイムスタンプを持つサンプルを探す
  let mut earliest_sample : ((UInt64, UInt64), Int32)? = None
  for track_index, track in self.tracks.iter2() {
    match track.table.get_sample(track.next_sample_index) {
      Some(sample_accessor) => {
        let timestamp = timestamp_key(
          sample_accessor.timestamp(),
          track.timescale.get().to_uint64(),
        )
        match earliest_sample {
          Some((earliest, _)) if !timestamp_before(timestamp, earliest) =>
            continue
          _ => earliest_sample = Some((timestamp, track_index))
        }
      }
      None => ()
    }
  }

  // 最も早いサンプルを提供したトラックを進める
  match earliest_sample {
    Some((_, track_index)) => {
      let sample_index = {
        let track = self.tracks[track_index]
        let sample_index = track.next_sample_index
        let next = sample_index.get()
        if next == 0xFFFFFFFFU {
          raise DemuxError::DecodeError(
            @bytes.Mp4Error::invalid_data("sample index overflow"),
          )
        }
        track.next_sample_index = @bytes.NonZeroU32::new(next + 1).unwrap()
        sample_index
      }
      Some(self.build_sample(track_index, sample_index))
    }
    None => None
  }
}

///|
/// 時系列順に前のサンプルを取得する。
///
/// 上流 `Mp4FileDemuxer::prev_sample` に対応する。
/// すべてのトラックのうち、現在位置より前にあるサンプルから、
/// 最も遅いタイムスタンプのものを返す。同一タイムスタンプのサンプルが
/// 複数ある場合は、シーク後の [`Mp4FileDemuxer::next_sample`] の
/// 走査対象に含まれる。サンプルが存在しない場合は `None`。
pub fn Mp4FileDemuxer::prev_sample(
  self : Mp4FileDemuxer,
) -> Sample? raise DemuxError {
  self.ensure_initialized()
  let mut latest_sample : ((UInt64, UInt64), Int32, @bytes.NonZeroU32)? = None

  // 全トラックの中で最も遅いタイムスタンプを持つサンプルを探す
  for track_index, track in self.tracks.iter2() {
    let prev_sample_index = match
      @bytes.NonZeroU32::new(track.next_sample_index.get() - 1) {
      Some(index) => index
      None => continue
    }
    match track.table.get_sample(prev_sample_index) {
      Some(sample_accessor) => {
        let timestamp = timestamp_key(
          sample_accessor.timestamp(),
          track.timescale.get().to_uint64(),
        )
        match latest_sample {
          Some((latest, _, _)) if !timestamp_after(timestamp, latest) =>
            continue
          _ => latest_sample = Some((timestamp, track_index, prev_sample_index))
        }
      }
      None => ()
    }
  }
  match latest_sample {
    Some((_, track_index, sample_index)) => {
      self.tracks[track_index].next_sample_index = sample_index
      Some(self.build_sample(track_index, sample_index))
    }
    None => None
  }
}

///|
/// 指定した時刻にシークする。
///
/// 上流 `Mp4FileDemuxer::seek` に対応する。
/// 各トラックで指定時刻を含むサンプルを選び、次回の
/// [`Mp4FileDemuxer::next_sample`] がその位置から開始されるようにする。
/// つまり次の `next_sample` で返されるサンプルのタイムスタンプは
/// 「`position` で指定した位置と同じか、少し前になることがある」。
pub fn Mp4FileDemuxer::seek(
  self : Mp4FileDemuxer,
  position : Duration,
) -> Unit raise DemuxError {
  self.ensure_initialized()
  for track in self.tracks {
    let target_timestamp = duration_to_timestamp(
      position,
      track.timescale.get().to_uint64(),
    )
    match track.table.get_sample_by_timestamp(target_timestamp) {
      Some(sample) => track.next_sample_index = sample.index()
      None => {
        let next_index = track.table.sample_count()
        if next_index == 0xFFFFFFFFU {
          raise DemuxError::DecodeError(
            @bytes.Mp4Error::invalid_data("sample index overflow"),
          )
        }
        track.next_sample_index = @bytes.NonZeroU32::new(next_index + 1).unwrap()
      }
    }
  }
}

///|
/// 上流 `Mp4FileDemuxer::build_sample` に対応する。
fn Mp4FileDemuxer::build_sample(
  self : Mp4FileDemuxer,
  track_index : Int32,
  sample_index : @bytes.NonZeroU32,
) -> Sample {
  let track = self.tracks[track_index]
  let sample_accessor = track.table.get_sample(sample_index).unwrap()
  let sample_entry = sample_accessor.chunk().sample_entry()
  let sample_entry_index = sample_accessor.chunk().sample_entry_index()

  // サンプルエントリーに変更があるかどうかをチェックする
  let is_new_sample_entry = match
    @bytes.NonZeroU32::new(sample_index.get() - 1) {
    Some(prev_sample_index) => {
      let prev_sample_accessor = track.table
        .get_sample(prev_sample_index)
        .unwrap()
      if prev_sample_accessor.chunk().sample_entry_index() == sample_entry_index {
        // サンプルエントリーのインデックスが等しい場合には、内容も常に等しい
        false
      } else {
        prev_sample_accessor.chunk().sample_entry() != sample_entry
      }
    }
    // 最初のサンプル
    None => true
  }
  {
    track: self.track_infos[track_index],
    sample_entry: if is_new_sample_entry {
      Some(sample_entry)
    } else {
      None
    },
    keyframe: sample_accessor.is_sync_sample(),
    timestamp: sample_accessor.timestamp(),
    duration: sample_accessor.duration(),
    data_offset: sample_accessor.data_offset(),
    data_size: sample_accessor.data_size(),
    composition_time_offset: sample_accessor.composition_time_offset(),
  }
}

///|
/// 上流 `Mp4FileDemuxer::ensure_initialized` に対応する。
///
/// 保持されたエラーは上流の `take()` と同じく一度だけ返す
/// （再度呼ばれた場合は `required_input` の状態から再評価される）。
fn Mp4FileDemuxer::ensure_initialized(
  self : Mp4FileDemuxer,
) -> Unit raise DemuxError {
  match self.handle_input_error {
    Some(e) => {
      self.handle_input_error = None
      raise e
    }
    None =>
      match self.required_input() {
        Some(required) => raise DemuxError::InputRequired(required)
        None => ()
      }
  }
}

///|
/// 上流の `From<SampleTableAccessorError> for DemuxError` 変換に対応する、
/// サンプルテーブルの失敗を [`DemuxError::SampleTableError`] に包むヘルパー。
fn[T] wrap_sample_table(
  f : () -> T raise @boxes.SampleTableAccessorError,
) -> T raise DemuxError {
  try f() catch {
    e => raise DemuxError::SampleTableError(e)
  } noraise {
    v => v
  }
}

///|
/// 上流の `Duration::from_secs(timestamp) / timescale` 比較に対応するキー。
///
/// 戻り値は (整数秒, 秒未満のナノ秒) で、上流の `Duration` 比較と同じく
/// 辞書順に評価する。浮動小数を経由しないため精度劣化は起こらない。
fn timestamp_key(timestamp : UInt64, timescale : UInt64) -> (UInt64, UInt64) {
  let secs = timestamp / timescale
  let carry = timestamp - secs * timescale
  let nanos = carry * nanos_per_sec / timescale
  (secs, nanos)
}

///|
/// `timestamp_key` の辞書順での小なり。
fn timestamp_before(a : (UInt64, UInt64), b : (UInt64, UInt64)) -> Bool {
  a.0 < b.0 || (a.0 == b.0 && a.1 < b.1)
}

///|
/// `timestamp_key` の辞書順での大なり。
fn timestamp_after(a : (UInt64, UInt64), b : (UInt64, UInt64)) -> Bool {
  timestamp_before(b, a)
}

///|
/// 上流 `duration_to_timestamp` に対応する。
///
/// `Duration` を `timescale` 単位のタイムスタンプに変換する。
/// 変換結果が `UInt64` に収まらない場合は
/// `"timestamp overflow"` の [`DemuxError::DecodeError`] を raise する。
fn duration_to_timestamp(
  duration : Duration,
  timescale : UInt64,
) -> UInt64 raise DemuxError {
  let secs_part = if duration.secs > 0xFFFF_FFFF_FFFF_FFFFUL / timescale {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data("timestamp overflow"),
    )
  } else {
    duration.secs * timescale
  }
  // `nanos` は 1e9 未満、`timescale` は u32 範囲なので積は溢れない
  let nanos_part = duration.nanos.to_uint64() * timescale / nanos_per_sec
  if secs_part > 0xFFFF_FFFF_FFFF_FFFFUL - nanos_part {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data("timestamp overflow"),
    )
  }
  secs_part + nanos_part
}
