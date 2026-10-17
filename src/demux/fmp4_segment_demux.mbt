// fMP4 の初期化セグメント + 単一メディアセグメントを処理する Sans I/O demuxer。
//
// `handle_init_segment()` で `moov`/`mvex` を読み、`handle_media_segment()` で
// `moof`/`mdat` からサンプル metadata を取り出す。返す `data_offset` は
// 渡したメディアセグメントの先頭からの相対位置であり、ファイル絶対位置ではない
// （ファイル全体を扱う `Fmp4FileDemuxer` が moof 位置を加算する）。

///|
/// 初期化済みトラックの実行時状態。
priv struct TrackRuntime {
  sample_entries : Array[@boxes.SampleEntry]
  trex : @boxes.TrexBox
  mut current_sample_description_index : UInt32?
}

///|
/// 初期化セグメントで読み飛ばしたトラック。
priv struct SkippedTrack {
  track_id : UInt32
  trex : @boxes.TrexBox?
}

///|
/// メディアセグメント処理中に保持するサンプル 1 件分の情報。
priv struct PendingSample {
  track_index : Int32
  sample_entry_index : Int32
  emit_sample_entry : Bool
  timestamp : UInt64
  duration : UInt32
  keyframe : Bool
  data_offset : Int32
  data_size : Int32
  composition_time_offset : Int64?
}

///|
/// fMP4 の初期化セグメントとメディアセグメントを処理する demuxer。
///
/// 初期化セグメントは 1 回だけ処理でき、2 回目は `InvalidState` になる。
/// メディアセグメントは 1 回の呼び出しにつき単一の `moof` + `mdat` ペアだけを
/// 受け付ける。
pub struct Fmp4SegmentDemuxer {
  priv mut track_infos : Array[TrackInfo]
  priv mut track_runtimes : Array[TrackRuntime]?
  priv mut skipped_tracks : Array[SkippedTrack]
}

///|
/// 新しい demuxer を作る。
pub fn Fmp4SegmentDemuxer::new() -> Fmp4SegmentDemuxer {
  { track_infos: [], track_runtimes: None, skipped_tracks: [], }
}

///|
/// 解析用の最大 `Int` 値（32-bit 環境を想定）。
let segment_max_int : UInt64 = 2147483647UL

///|
/// `UInt64` を安全に `Int` へ変換する。
fn segment_to_int(value : UInt64) -> Int32 raise DemuxError {
  if value > segment_max_int {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data("value exceeds Int range"),
    )
  }
  value.to_int()
}

///|
/// `Mp4Error` を `DemuxError::DecodeError` で包む。
fn[T] segment_wrap(f : () -> T raise @bytes.Mp4Error) -> T raise DemuxError {
  try f() catch {
    e => raise DemuxError::DecodeError(e)
  } noraise {
    v => v
  }
}

///|
/// `data` の `start` 以降から `needle` のボックスを探し、その先頭位置を返す。
fn segment_find_box(
  data : BytesView,
  start : Int32,
  needle : Bytes,
  missing_message : String,
) -> Int32 raise DemuxError {
  let mut offset = start
  while offset < data.length() {
    let cursor = @bytes.ReadCursor::from_view(data[offset:], offset.to_uint64())
    let (header, _payload) = segment_wrap(fn() raise @bytes.Mp4Error {
      @box.BoxHeader::decode_header_and_payload(cursor)
    })
    if header.box_type().as_bytes() == needle {
      return offset
    }
    if header.box_size().get() == 0UL {
      raise DemuxError::DecodeError(
        @bytes.Mp4Error::invalid_data(
          "found box with size=0 before the target box in media segment",
        ),
      )
    }
    offset = offset + header.external_size() + _payload.length()
  }
  raise DemuxError::DecodeError(@bytes.Mp4Error::invalid_data(missing_message))
}

///|
/// 初期化セグメントからトラック情報と `trex` を読み込む。
///
/// `ftyp` などは任意で、`moov` が必須。`mvex` が無い場合は fMP4 の初期化
/// セグメントではないとして失敗する。登録対象トラックに `trex` が無い場合や
/// `stsd` が空の場合も失敗する。
pub fn Fmp4SegmentDemuxer::handle_init_segment(
  self : Fmp4SegmentDemuxer,
  data : Bytes,
) -> Unit raise DemuxError {
  self.handle_init_segment_view(data[:])
}

///|
/// [`handle_init_segment`] の view 版（コピーを避ける内部 API）。
fn Fmp4SegmentDemuxer::handle_init_segment_view(
  self : Fmp4SegmentDemuxer,
  data : BytesView,
) -> Unit raise DemuxError {
  if self.track_runtimes is Some(_) {
    raise DemuxError::InvalidState("Init segment has already been processed")
  }
  let moov_offset = segment_find_box(
    data, 0, b"moov", "moov box not found in init segment",
  )
  let moov_cursor = @bytes.ReadCursor::from_view(
    data[moov_offset:],
    moov_offset.to_uint64(),
  )
  let moov_box : @boxes.MoovBox = segment_wrap(fn() raise @bytes.Mp4Error {
    @bytes.decode_from(moov_cursor)
  })
  let mvex_box = match moov_box.mvex_box() {
    Some(mvex) => mvex
    None =>
      raise DemuxError::DecodeError(
        @bytes.Mp4Error::invalid_data(
          "moov box does not contain mvex box (not an fMP4 init segment)",
        ),
      )
  }
  let trex_list = mvex_box.trex_boxes
  let track_infos : Array[TrackInfo] = []
  let track_runtimes : Array[TrackRuntime] = []
  let skipped_tracks : Array[SkippedTrack] = []
  for trak in moov_box.trak_boxes {
    let track_id = trak.tkhd_box.track_id
    let kind = match trak.mdia_box.hdlr_box.track_kind() {
      Some(kind) => kind
      None => {
        // 映像・音声・字幕以外のトラックはサンプルを返さない。
        // 後続 `traf` を読み飛ばすために track_id と trex だけ記録する。
        let mut trex : @boxes.TrexBox? = None
        for candidate in trex_list {
          if candidate.track_id == track_id {
            trex = Some(candidate)
          }
        }
        skipped_tracks.push({ track_id, trex, })
        continue
      }
    }
    let sample_entries = trak.mdia_box.minf_box.stbl_box.stsd_box.entries
    if sample_entries.length() == 0 {
      raise DemuxError::DecodeError(
        @bytes.Mp4Error::invalid_data(
          "stsd box is empty for track_id=\{track_id}",
        ),
      )
    }
    let mut trex : @boxes.TrexBox? = None
    for candidate in trex_list {
      if candidate.track_id == track_id {
        trex = Some(candidate)
      }
    }
    let trex = match trex {
      Some(trex) => trex
      None =>
        raise DemuxError::DecodeError(
          @bytes.Mp4Error::invalid_data(
            "trex not found for track_id=\{track_id}",
          ),
        )
    }
    track_infos.push(TrackInfo::{
      track_id,
      kind,
      duration: trak.mdia_box.mdhd_box.duration,
      timescale: trak.mdia_box.mdhd_box.timescale,
    })
    track_runtimes.push({
      sample_entries,
      trex,
      current_sample_description_index: None,
    })
  }
  self.track_infos = track_infos
  self.track_runtimes = Some(track_runtimes)
  self.skipped_tracks = skipped_tracks
}

///|
/// 初期化済みのトラック情報を返す。
pub fn Fmp4SegmentDemuxer::tracks(
  self : Fmp4SegmentDemuxer,
) -> Array[TrackInfo] raise DemuxError {
  match self.track_runtimes {
    Some(_) => self.track_infos
    None =>
      raise DemuxError::InvalidState("Init segment has not been processed yet")
  }
}

///|
/// `tfhd` の基準位置を決める。
fn segment_traf_base_data_offset(
  traf : @boxes.TrafBox,
  moof_offset : Int32,
  prev_traf_data_end : Int32?,
) -> Int32 raise DemuxError {
  let tfhd = traf.tfhd_box
  match tfhd.base_data_offset {
    Some(explicit) => segment_to_int(explicit)
    None =>
      if tfhd.default_base_is_moof {
        moof_offset
      } else {
        match prev_traf_data_end {
          Some(end) => end
          None => moof_offset
        }
      }
  }
}

///|
/// `trun` のデータ開始位置を決める。
fn segment_trun_data_start(
  trun : @boxes.TrunBox,
  base_data_offset : Int32,
  prev_trun_data_end : Int32?,
) -> Int32 raise DemuxError {
  match trun.data_offset {
    Some(data_offset) => {
      let value = base_data_offset.to_int64() + data_offset.to_int64()
      if value < 0L {
        raise DemuxError::DecodeError(
          @bytes.Mp4Error::invalid_data("trun data_offset is before the buffer"),
        )
      }
      segment_to_int(value.reinterpret_as_uint64())
    }
    None =>
      match prev_trun_data_end {
        Some(end) => end
        None => base_data_offset
      }
  }
}

///|
/// サンプルサイズを `trun` → `tfhd` → `trex` の順で解決する。
fn segment_sample_size(
  trun_sample : @boxes.TrunSample,
  tfhd : @boxes.TfhdBox,
  trex : @boxes.TrexBox?,
) -> UInt32? {
  match trun_sample.size {
    Some(size) => Some(size)
    None =>
      match tfhd.default_sample_size {
        Some(size) => Some(size)
        None =>
          match trex {
            Some(trex) => Some(trex.default_sample_size)
            None => None
          }
      }
  }
}

///|
/// sample_description_index を `tfhd` → `trex` の順で解決する。
fn segment_sample_description_index(
  tfhd : @boxes.TfhdBox,
  trex : @boxes.TrexBox,
) -> UInt32 raise DemuxError {
  let index = match tfhd.sample_description_index {
    Some(index) => index
    None => trex.default_sample_description_index
  }
  if index == 0U {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data(
        "sample_description_index must be greater than zero",
      ),
    )
  }
  index
}

///|
/// sample_description_index を `stsd` の 0-based index へ変換する。
fn segment_sample_entry_index(
  runtime : TrackRuntime,
  index : UInt32,
  track_id : UInt32,
) -> Int32 raise DemuxError {
  let zero_based = index.reinterpret_as_int() - 1
  if zero_based < 0 || zero_based >= runtime.sample_entries.length() {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data(
        "sample_description_index=\{index} is out of range for track_id=\{track_id}",
      ),
    )
  }
  zero_based
}

///|
/// 読み飛ばす `traf` のデータ末尾を計算する。
fn segment_skipped_traf_data_end(
  traf : @boxes.TrafBox,
  skipped : SkippedTrack,
  moof_offset : Int32,
  prev_traf_data_end : Int32?,
) -> Int32 raise DemuxError {
  let base = segment_traf_base_data_offset(
    traf, moof_offset, prev_traf_data_end,
  )
  let mut traf_data_end = base
  let mut prev_trun_data_end : Int32? = None
  for trun in traf.trun_boxes {
    let mut sample_offset = segment_trun_data_start(
      trun, base, prev_trun_data_end,
    )
    for sample in trun.samples {
      let size = match
        segment_sample_size(sample, traf.tfhd_box, skipped.trex) {
        Some(size) => size
        None =>
          raise DemuxError::DecodeError(
            @bytes.Mp4Error::invalid_data(
              "trex not found for skipped track_id=\{skipped.track_id}",
            ),
          )
      }
      sample_offset = sample_offset + size.reinterpret_as_int()
    }
    prev_trun_data_end = Some(sample_offset)
    traf_data_end = if traf_data_end > sample_offset {
      traf_data_end
    } else {
      sample_offset
    }
  }
  traf_data_end
}

///|
/// メディアセグメントを処理してサンプルを返す。
///
/// 返す `data_offset` は渡した `data` の先頭からの相対位置である。
/// エラー時は内部状態を変更しない。
pub fn Fmp4SegmentDemuxer::handle_media_segment(
  self : Fmp4SegmentDemuxer,
  data : Bytes,
) -> Array[Sample] raise DemuxError {
  self.handle_media_segment_view(data[:], allow_base_data_offset=true)
}

///|
/// [`handle_media_segment`] の view 版（コピーを避ける内部 API）。
///
/// `allow_base_data_offset=false` の場合は `tfhd.base_data_offset` を
/// 含む `traf` をエラーにする（ファイル全体の demux 用）。
fn Fmp4SegmentDemuxer::handle_media_segment_view(
  self : Fmp4SegmentDemuxer,
  data : BytesView,
  allow_base_data_offset~ : Bool,
) -> Array[Sample] raise DemuxError {
  if data.length() == 0 {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_input("empty media segment"),
    )
  }
  let track_runtimes = match self.track_runtimes {
    Some(runtimes) => runtimes
    None =>
      raise DemuxError::InvalidState("Init segment has not been processed yet")
  }
  let moof_offset = segment_find_box(
    data, 0, b"moof", "moof box not found in media segment",
  )
  let moof_cursor = @bytes.ReadCursor::from_view(
    data[moof_offset:],
    moof_offset.to_uint64(),
  )
  let moof_box : @boxes.MoofBox = segment_wrap(fn() raise @bytes.Mp4Error {
    @bytes.decode_from(moof_cursor)
  })
  let moof_size = moof_cursor.position()
  let mdat_search_start = moof_offset + moof_size
  let mdat_offset = segment_find_box(
    data, mdat_search_start, b"mdat", "mdat box not found after moof",
  )
  let mdat_cursor = @bytes.ReadCursor::from_view(
    data[mdat_offset:],
    mdat_offset.to_uint64(),
  )
  let (mdat_header, mdat_payload) = segment_wrap(fn() raise @bytes.Mp4Error {
    @box.BoxHeader::decode_header_and_payload(mdat_cursor)
  })
  let mdat_end = if mdat_header.box_size().get() == 0UL {
    data.length()
  } else {
    mdat_offset + mdat_header.external_size() + mdat_payload.length()
  }
  if mdat_end > data.length() {
    raise DemuxError::DecodeError(
      @bytes.Mp4Error::invalid_data("mdat box exceeds segment boundary"),
    )
  }

  // 作業用に直前の sample_description_index を複製する。エラー時は書き戻さない。
  let current_indices : Array[UInt32?] = []
  for runtime in track_runtimes {
    current_indices.push(runtime.current_sample_description_index)
  }
  let pending : Array[PendingSample] = []
  let mut prev_traf_data_end : Int32? = None
  for traf in moof_box.traf_boxes {
    let track_index = segment_find_track_index(
      self.track_infos,
      traf.tfhd_box.track_id,
    )
    let track_index = match track_index {
      Some(index) => index
      None => {
        let mut skipped : SkippedTrack? = None
        for candidate in self.skipped_tracks {
          if candidate.track_id == traf.tfhd_box.track_id {
            skipped = Some(candidate)
          }
        }
        let skipped = match skipped {
          Some(skipped) => skipped
          None =>
            raise DemuxError::DecodeError(
              @bytes.Mp4Error::invalid_data(
                "unknown track_id in media segment: \{traf.tfhd_box.track_id}",
              ),
            )
        }
        prev_traf_data_end = Some(
          segment_skipped_traf_data_end(
            traf, skipped, moof_offset, prev_traf_data_end,
          ),
        )
        continue
      }
    }
    if !allow_base_data_offset && traf.tfhd_box.base_data_offset is Some(_) {
      raise DemuxError::DecodeError(
        @bytes.Mp4Error::invalid_data(
          "tfhd.base_data_offset absolute form is not supported by Fmp4FileDemuxer",
        ),
      )
    }
    let runtime = track_runtimes[track_index]
    let sample_description_index = segment_sample_description_index(
      traf.tfhd_box,
      runtime.trex,
    )
    let sample_entry_index = segment_sample_entry_index(
      runtime,
      sample_description_index,
      self.track_infos[track_index].track_id,
    )
    let mut emit_sample_entry = current_indices[track_index] !=
      Some(sample_description_index)
    let base_media_decode_time = match traf.tfdt_box {
      Some(tfdt) => tfdt.base_media_decode_time
      None => 0UL
    }
    let base_data_offset = segment_traf_base_data_offset(
      traf, moof_offset, prev_traf_data_end,
    )
    let mut trun_decode_time = base_media_decode_time
    let mut traf_data_end = base_data_offset
    let mut prev_trun_data_end : Int32? = None
    for trun in traf.trun_boxes {
      let trun_data_start = segment_trun_data_start(
        trun, base_data_offset, prev_trun_data_end,
      )
      let mut sample_data_offset = trun_data_start
      let mut sample_index = 0
      for trun_sample in trun.samples {
        let duration = match trun_sample.duration {
          Some(duration) => duration
          None =>
            match traf.tfhd_box.default_sample_duration {
              Some(duration) => duration
              None => runtime.trex.default_sample_duration
            }
        }
        let size_u32 = match
          segment_sample_size(trun_sample, traf.tfhd_box, Some(runtime.trex)) {
          Some(size) => size
          None =>
            raise DemuxError::DecodeError(
              @bytes.Mp4Error::invalid_data("sample size is not defined"),
            )
        }
        let size = size_u32.reinterpret_as_int()
        let flags = if sample_index == 0 && trun.first_sample_flags is Some(_) {
          match trun.first_sample_flags {
            Some(flags) => flags
            None => @boxes.SampleFlags::empty()
          }
        } else {
          match trun_sample.flags {
            Some(flags) => flags
            None =>
              match traf.tfhd_box.default_sample_flags {
                Some(flags) => flags
                None => runtime.trex.default_sample_flags
              }
          }
        }
        let keyframe = !flags.sample_is_non_sync_sample()
        let sample_data_end = sample_data_offset + size
        if sample_data_end > mdat_end {
          raise DemuxError::DecodeError(
            @bytes.Mp4Error::invalid_data(
              "sample data range exceeds mdat boundary",
            ),
          )
        }
        pending.push({
          track_index,
          sample_entry_index,
          emit_sample_entry,
          timestamp: trun_decode_time,
          duration,
          keyframe,
          data_offset: sample_data_offset,
          data_size: size,
          composition_time_offset: trun_sample.composition_time_offset,
        })
        current_indices[track_index] = Some(sample_description_index)
        emit_sample_entry = false
        trun_decode_time = trun_decode_time + duration.to_uint64()
        sample_data_offset = sample_data_end
        sample_index = sample_index + 1
      }
      prev_trun_data_end = Some(sample_data_offset)
      traf_data_end = if traf_data_end > sample_data_offset {
        traf_data_end
      } else {
        sample_data_offset
      }
    }
    prev_traf_data_end = Some(traf_data_end)
  }

  // mdat の後ろは入力末尾まで読み飛ばす。size=0 は末尾まで続くボックスとして扱う。
  let mut trailing = mdat_end
  while trailing < data.length() {
    let cursor = @bytes.ReadCursor::from_view(
      data[trailing:],
      trailing.to_uint64(),
    )
    let (header, payload) = segment_wrap(fn() raise @bytes.Mp4Error {
      @box.BoxHeader::decode_header_and_payload(cursor)
    })
    if header.box_type().as_bytes() == b"moof" {
      raise DemuxError::DecodeError(
        @bytes.Mp4Error::invalid_data(
          "found moof box after mdat in media segment",
        ),
      )
    }
    if header.box_size().get() == 0UL {
      break
    }
    trailing = trailing + header.external_size() + payload.length()
  }

  // ここまで成功したので、sample_description_index を書き戻す。
  let mut index = 0
  while index < track_runtimes.length() {
    track_runtimes[index].current_sample_description_index = current_indices[index]
    index = index + 1
  }

  let samples : Array[Sample] = []
  for p in pending {
    let entry = if p.emit_sample_entry {
      Some(track_runtimes[p.track_index].sample_entries[p.sample_entry_index])
    } else {
      None
    }
    samples.push(Sample::{
      track: self.track_infos[p.track_index],
      sample_entry: entry,
      keyframe: p.keyframe,
      timestamp: p.timestamp,
      duration: p.duration,
      data_offset: p.data_offset.to_uint64(),
      data_size: p.data_size.reinterpret_as_uint(),
      composition_time_offset: p.composition_time_offset,
    })
  }
  samples
}

///|
/// track_id から登録対象トラックの index を探す。
fn segment_find_track_index(
  track_infos : Array[TrackInfo],
  track_id : UInt32,
) -> Int32? {
  let mut index = 0
  while index < track_infos.length() {
    if track_infos[index].track_id == track_id {
      return Some(index)
    }
    index = index + 1
  }
  None
}
