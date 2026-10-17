///|
/// [`Mp4FileMuxer`] のオプション。
pub struct Mp4FileMuxerOptions {
  /// faststart 用に事前確保する moov のサイズ（バイト）
  reserved_moov_box_size : UInt64
  /// 作成時刻（UNIX 秒）
  creation_timestamp : UInt64
  /// トラックメタデータ
  tracks : TrackMetadataOptions
} derive(Eq, Hash, Debug)

///|
pub extend Mp4FileMuxerOptions with Eq::{equal, not_equal}

///|
pub extend Mp4FileMuxerOptions with Hash::{hash, hash_combine}

///|
pub extend Mp4FileMuxerOptions with Debug::{to_repr}

///|
/// 各フィールドを指定してオプションを作る。
pub fn Mp4FileMuxerOptions::new(
  reserved_moov_box_size : UInt64,
  creation_timestamp : UInt64,
  tracks : TrackMetadataOptions,
) -> Mp4FileMuxerOptions {
  { reserved_moov_box_size, creation_timestamp, tracks, }
}

///|
/// 既定のオプション。
pub fn Mp4FileMuxerOptions::default() -> Mp4FileMuxerOptions {
  {
    reserved_moov_box_size: 0UL,
    creation_timestamp: 0UL,
    tracks: TrackMetadataOptions::default(),
  }
}

///|
/// ファイナライズ結果として書き込むボックス群。
pub struct FinalizedBoxes {
  priv head_boxes_bytes : Bytes
  priv moov_box_offset : UInt64
  priv moov_box_bytes : Bytes
  priv mdat_box_offset : UInt64
  priv mdat_box_header_bytes : Bytes
  priv moov_box : @boxes.MoovBox
} derive(Debug)

///|
pub extend FinalizedBoxes with Debug::{to_repr}

///|
/// faststart が有効かどうか。
pub fn FinalizedBoxes::is_faststart_enabled(self : FinalizedBoxes) -> Bool {
  self.moov_box_offset < self.mdat_box_offset
}

///|
/// moov のサイズ。
pub fn FinalizedBoxes::moov_box_size(self : FinalizedBoxes) -> Int32 {
  self.moov_box_bytes.length()
}

///|
/// 書き込むべき `(offset, bytes)` の列を返す。
pub fn FinalizedBoxes::offset_and_bytes_pairs(
  self : FinalizedBoxes,
) -> Array[(UInt64, Bytes)] {
  let pairs : Array[(UInt64, Bytes)] = []
  pairs.push((0UL, self.head_boxes_bytes))
  if self.moov_box_offset >= self.mdat_box_offset {
    pairs.push((self.moov_box_offset, self.moov_box_bytes))
  }
  pairs.push((self.mdat_box_offset, self.mdat_box_header_bytes))
  pairs
}

///|
/// moov の書き込み位置を返す。
pub fn FinalizedBoxes::moov_box_offset(self : FinalizedBoxes) -> UInt64 {
  self.moov_box_offset
}

///|
/// mdat の書き込み位置を返す。
pub fn FinalizedBoxes::mdat_box_offset(self : FinalizedBoxes) -> UInt64 {
  self.mdat_box_offset
}

///|
/// 構築された moov を返す。
pub fn FinalizedBoxes::moov_box(self : FinalizedBoxes) -> @boxes.MoovBox {
  self.moov_box
}

///|
/// ファイナライズ前の 1 サンプル。
priv struct FileSample {
  duration : UInt32
  keyframe : Bool
  size : UInt32
  composition_time_offset : Int64?
}

///|
/// チャンク。
priv struct FileChunk {
  sample_entry_index : UInt32
  data_offset : UInt64
  samples : Array[FileSample]
}

///|
/// トラック状態。
priv struct FileTrackEntry {
  track_kind : @bytes.TrackKind
  timescale : @bytes.NonZeroU32
  sample_entries : Array[@boxes.SampleEntry]
  chunks : Array[FileChunk]
  mut duration : UInt64
  mut sample_count : UInt64
  mut keyframe_count : UInt64
}

///|
/// 通常 MP4 ファイルを生成する muxer。
pub struct Mp4FileMuxer {
  priv options : Mp4FileMuxerOptions
  priv initial_boxes_bytes : Bytes
  priv mdat_box_offset : UInt64
  priv mut next_position : UInt64
  priv mut last_sample_kind : @bytes.TrackKind?
  priv mut finalized : FinalizedBoxes?
  priv tracks : Array[FileTrackEntry]
}

///|
/// 新しい muxer を作る。
pub fn Mp4FileMuxer::new() -> Mp4FileMuxer raise MuxError {
  Mp4FileMuxer::with_options(Mp4FileMuxerOptions::default())
}

///|
/// オプションを指定して muxer を作る。
pub fn Mp4FileMuxer::with_options(
  options : Mp4FileMuxerOptions,
) -> Mp4FileMuxer raise MuxError {
  let ftyp = @boxes.FtypBox::new(mux_brand("isom"), 0U, [
    mux_brand("isom"),
    mux_brand("iso2"),
    mux_brand("mp41"),
  ])
  let ftyp_bytes = wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(ftyp)
  })
  let reserved = options.reserved_moov_box_size.to_int()
  let free = @boxes.FreeBox::new(Bytes::make(reserved + 64, b'\x00'))
  let free_bytes = wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(free)
  })
  let mdat_offset = (ftyp_bytes.length() + free_bytes.length()).to_uint64()
  let mdat_header = wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(
      @box.BoxHeader::new(mux_mdat_type(), @box.BoxSize::U64(16UL)),
    )
  })
  let initial = ftyp_bytes + free_bytes + mdat_header
  {
    options,
    initial_boxes_bytes: initial,
    mdat_box_offset: mdat_offset,
    next_position: initial.length().to_uint64(),
    last_sample_kind: None,
    finalized: None,
    tracks: [],
  }
}

///|
/// 初期ボックス群を返す。
pub fn Mp4FileMuxer::initial_boxes_bytes(self : Mp4FileMuxer) -> Bytes {
  self.initial_boxes_bytes
}

///|
/// サンプル以外のバイト列分だけ書き込み位置を進める。
pub fn Mp4FileMuxer::advance_position(
  self : Mp4FileMuxer,
  size : UInt64,
) -> Unit raise MuxError {
  if self.finalized is Some(_) {
    raise MuxError::AlreadyFinalized
  }
  let next = self.next_position + size
  if next < self.next_position {
    raise MuxError::Overflow
  }
  self.next_position = next
  if size > 0UL {
    self.last_sample_kind = None
  }
}

///|
/// サンプルを追記したことを通知する。
pub fn Mp4FileMuxer::append_sample(
  self : Mp4FileMuxer,
  sample : Sample,
) -> Unit raise MuxError {
  if self.finalized is Some(_) {
    raise MuxError::AlreadyFinalized
  }
  if self.next_position != sample.data_offset {
    raise MuxError::PositionMismatch(
      expected=self.next_position,
      actual=sample.data_offset,
    )
  }
  let track_index = self.ensure_file_track(sample.track_kind, sample.timescale)
  let track = self.tracks[track_index]
  let last_entry_index = if track.chunks.length() > 0 {
    Some(track.chunks[track.chunks.length() - 1].sample_entry_index)
  } else {
    None
  }
  let resolved_entry_index = self.resolve_entry_index(
    track,
    sample.sample_entry,
  )
  // チャンク先頭で entry が変わる場合に備え、必要なら stsd へ追加する。
  let mut entry_index = resolved_entry_index
  let is_new_chunk = self.last_sample_kind != Some(sample.track_kind) ||
    last_entry_index is None ||
    last_entry_index != Some(entry_index)
  if is_new_chunk {
    let entry = match sample.sample_entry {
      Some(entry) => entry
      None =>
        match track.chunks.length() {
          0 => raise MuxError::MissingSampleEntry(track_kind=sample.track_kind)
          _ => {
            let idx = track.chunks[track.chunks.length() - 1].sample_entry_index
            track.sample_entries[idx.reinterpret_as_int() - 1]
          }
        }
    }
    if sample.track_kind == @bytes.TrackKind::Subtitle {
      if track.sample_entries.length() > 0 {
        let first = track.sample_entries[0]
        let (first_handler, first_header) = subtitle_trak_attributes(first)
        let (handler, header) = subtitle_trak_attributes(entry)
        if first_handler != handler || first_header != header {
          raise MuxError::MixedSampleEntries(track_kind=sample.track_kind)
        }
      }
    }
    entry_index = self.find_or_add_entry(track, entry)
    track.chunks.push({
      sample_entry_index: entry_index,
      data_offset: sample.data_offset,
      samples: [],
    })
  }
  let chunk_index = track.chunks.length() - 1
  track.chunks[chunk_index].samples.push({
    duration: sample.duration,
    keyframe: sample.keyframe,
    size: sample.data_size,
    composition_time_offset: sample.composition_time_offset,
  })
  track.duration = track.duration + sample.duration.to_uint64()
  track.sample_count = track.sample_count + 1UL
  if sample.keyframe {
    track.keyframe_count = track.keyframe_count + 1UL
  }
  self.next_position = sample.data_offset + sample.data_size.to_uint64()
  self.last_sample_kind = Some(sample.track_kind)
}

///|
/// トラックを取得または追加する。
fn Mp4FileMuxer::ensure_file_track(
  self : Mp4FileMuxer,
  kind : @bytes.TrackKind,
  timescale : @bytes.NonZeroU32,
) -> Int32 raise MuxError {
  let mut index = 0
  while index < self.tracks.length() {
    if self.tracks[index].track_kind == kind {
      if self.tracks[index].timescale != timescale {
        raise MuxError::TimescaleMismatch(
          track_kind=kind,
          expected=self.tracks[index].timescale,
          actual=timescale,
        )
      }
      return index
    }
    index = index + 1
  }
  self.tracks.push({
    track_kind: kind,
    timescale,
    sample_entries: [],
    chunks: [],
    duration: 0UL,
    sample_count: 0UL,
    keyframe_count: 0UL,
  })
  self.tracks.length() - 1
}

///|
/// `sample_entry` の stsd index（1 始まり）を返す。`None` は直前の entry を使う。
fn Mp4FileMuxer::resolve_entry_index(
  self : Mp4FileMuxer,
  track : FileTrackEntry,
  sample_entry : @boxes.SampleEntry?,
) -> UInt32 raise MuxError {
  match sample_entry {
    Some(entry) => self.find_or_add_entry(track, entry)
    None =>
      if track.chunks.length() > 0 {
        track.chunks[track.chunks.length() - 1].sample_entry_index
      } else if track.sample_entries.length() > 0 {
        1U
      } else {
        raise MuxError::MissingSampleEntry(track_kind=track.track_kind)
      }
  }
}

///|
/// stsd 内の entry index（1 始まり）を返す。無ければ追加する。
fn Mp4FileMuxer::find_or_add_entry(
  _self : Mp4FileMuxer,
  track : FileTrackEntry,
  entry : @boxes.SampleEntry,
) -> UInt32 {
  let mut index = 0
  while index < track.sample_entries.length() {
    if track.sample_entries[index] == entry {
      return (index + 1).reinterpret_as_uint()
    }
    index = index + 1
  }
  track.sample_entries.push(entry)
  track.sample_entries.length().reinterpret_as_uint()
}

///|
/// すべてのサンプル追加が完了したことを通知し、書き込み用のボックス群を返す。
pub fn Mp4FileMuxer::finalize(
  self : Mp4FileMuxer,
) -> FinalizedBoxes raise MuxError {
  if self.finalized is Some(_) {
    raise MuxError::AlreadyFinalized
  }
  let time = @bytes.Mp4FileTime::from_unix_seconds(
    self.options.creation_timestamp,
  )
  let traks : Array[@boxes.TrakBox] = []
  let mut movie_duration : UInt64 = 0UL
  for track in self.tracks {
    let movie_duration_track = track.duration *
      1000UL /
      track.timescale.get().to_uint64()
    if movie_duration_track > movie_duration {
      movie_duration = movie_duration_track
    }
    traks.push(self.build_file_trak(track, time, movie_duration_track))
  }
  let mvhd = @boxes.MvhdBox::new(
    time,
    time,
    @bytes.NonZeroU32::new(1000U).unwrap(),
    movie_duration,
    @boxes.MvhdBox::default_rate(),
    @boxes.MvhdBox::default_volume(),
    @boxes.MvhdBox::default_matrix(),
    (self.tracks.length() + 1).reinterpret_as_uint(),
  )
  let moov = @boxes.MoovBox::new(mvhd, traks, [])
  let moov_bytes = wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(moov)
  })
  let ftyp_bytes = self.build_final_ftyp_bytes()
  let head_len = self.mdat_box_offset.to_int() + 16
  let free_total = head_len - ftyp_bytes.length() - 16
  let faststart = free_total >= moov_bytes.length() + 8
  let (head_boxes_bytes, moov_box_offset) = if faststart {
    let free_payload = free_total - moov_bytes.length() - 8
    let free = @boxes.FreeBox::new(Bytes::make(free_payload, b'\x00'))
    let free_bytes = wrap_mux_encode(fn() raise @bytes.Mp4Error {
      @bytes.encode_to_bytes(free)
    })
    (
      ftyp_bytes + moov_bytes + free_bytes + self.mdat_header_bytes(),
      (ftyp_bytes.length() + moov_bytes.length()).to_uint64(),
    )
  } else {
    let free_payload = if free_total >= 8 { free_total - 8 } else { 0 }
    let free = @boxes.FreeBox::new(Bytes::make(free_payload, b'\x00'))
    let free_bytes = wrap_mux_encode(fn() raise @bytes.Mp4Error {
      @bytes.encode_to_bytes(free)
    })
    (ftyp_bytes + free_bytes + self.mdat_header_bytes(), self.next_position)
  }
  let finalized = {
    head_boxes_bytes,
    moov_box_offset,
    moov_box_bytes: moov_bytes,
    mdat_box_offset: self.mdat_box_offset,
    mdat_box_header_bytes: self.mdat_header_bytes(),
    moov_box: moov,
  }
  self.finalized = Some(finalized)
  finalized
}

///|
/// ファイナライズ済みの結果を返す。
pub fn Mp4FileMuxer::finalized_boxes(self : Mp4FileMuxer) -> FinalizedBoxes? {
  self.finalized
}

///|
/// 最終的な `ftyp` を生成する。
fn Mp4FileMuxer::build_final_ftyp_bytes(
  self : Mp4FileMuxer,
) -> Bytes raise MuxError {
  let brands = [mux_brand("isom"), mux_brand("iso2"), mux_brand("mp41")]
  let mut has_avc1 = false
  let mut has_hev1 = false
  let mut has_hvc1 = false
  let mut has_av01 = false
  for track in self.tracks {
    for entry in track.sample_entries {
      match entry {
        @boxes.SampleEntry::Avc1(_) => has_avc1 = true
        @boxes.SampleEntry::Hev1(_) => has_hev1 = true
        @boxes.SampleEntry::Hvc1(_) => has_hvc1 = true
        @boxes.SampleEntry::Av01(_) => has_av01 = true
        _ => ()
      }
    }
  }
  if has_avc1 {
    brands.push(mux_brand("avc1"))
  }
  if has_hev1 {
    brands.push(mux_brand("hev1"))
  }
  if has_hvc1 {
    brands.push(mux_brand("hvc1"))
  }
  if has_av01 {
    brands.push(mux_brand("av01"))
  }
  let ftyp = @boxes.FtypBox::new(mux_brand("isom"), 0U, brands)
  wrap_mux_encode(fn() raise @bytes.Mp4Error { @bytes.encode_to_bytes(ftyp) })
}

///|
/// `mdat` ヘッダーを返す。
fn Mp4FileMuxer::mdat_header_bytes(self : Mp4FileMuxer) -> Bytes raise MuxError {
  let size = self.next_position - self.mdat_box_offset
  wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(
      @box.BoxHeader::new(mux_mdat_type(), @box.BoxSize::U64(size)),
    )
  })
}

///|
/// 1 トラック分の `trak` を生成する。
fn Mp4FileMuxer::build_file_trak(
  self : Mp4FileMuxer,
  track : FileTrackEntry,
  time : @bytes.Mp4FileTime,
  movie_duration : UInt64,
) -> @boxes.TrakBox raise MuxError {
  let first = track.sample_entries[0]
  let (volume, width, height, handler, media_header) = match track.track_kind {
    @bytes.TrackKind::Video => {
      let (w, h) = match first.video_resolution() {
        Some((w, h)) => (w, h)
        None => (0U, 0U)
      }
      (
        @boxes.TkhdBox::default_video_volume(),
        @bytes.FixedPointNumber::new(w.reinterpret_as_int(), 0),
        @bytes.FixedPointNumber::new(h.reinterpret_as_int(), 0),
        @boxes.HdlrBox::handler_type_vide(),
        @boxes.MediaHeader::Vmhd(
          @boxes.VmhdBox::new(
            @boxes.VmhdBox::default_graphicsmode(),
            @boxes.VmhdBox::default_opcolor(),
          ),
        ),
      )
    }
    @bytes.TrackKind::Audio =>
      (
        @boxes.TkhdBox::default_audio_volume(),
        @bytes.FixedPointNumber::new(0, 0),
        @bytes.FixedPointNumber::new(0, 0),
        @boxes.HdlrBox::handler_type_soun(),
        @boxes.MediaHeader::Smhd(
          @boxes.SmhdBox::new(@boxes.SmhdBox::default_balance()),
        ),
      )
    @bytes.TrackKind::Subtitle => {
      let (handler, media_header) = subtitle_trak_attributes(first)
      (
        @boxes.TkhdBox::default_video_volume(),
        @bytes.FixedPointNumber::new(0, 0),
        @bytes.FixedPointNumber::new(0, 0),
        handler,
        media_header,
      )
    }
  }
  let metadata = self.options.tracks.for_kind(track.track_kind)
  let tkhd = @boxes.TkhdBox::new(
    true,
    true,
    false,
    false,
    time,
    time,
    (self.track_index(track.track_kind) + 1).reinterpret_as_uint(),
    movie_duration,
    @boxes.TkhdBox::default_layer(),
    @boxes.TkhdBox::default_alternate_group(),
    volume,
    @boxes.TkhdBox::default_matrix(),
    width,
    height,
  )
  let hdlr = @boxes.HdlrBox::new(
    handler,
    metadata.name.into_null_terminated_bytes(),
  )
  let mdhd = @boxes.MdhdBox::new(
    time,
    time,
    track.timescale,
    track.duration,
    metadata.language,
  )
  let stbl = self.build_file_stbl(track)
  let minf = @boxes.MinfBox::new(
    Some(media_header),
    @boxes.DinfBox::local_file(),
    stbl,
    [],
  )
  let mdia = @boxes.MdiaBox::new(mdhd, hdlr, minf, [])
  @boxes.TrakBox::new(tkhd, None, mdia, [])
}

///|
/// トラックの index を返す。
fn Mp4FileMuxer::track_index(
  self : Mp4FileMuxer,
  kind : @bytes.TrackKind,
) -> Int32 {
  let mut index = 0
  while index < self.tracks.length() {
    if self.tracks[index].track_kind == kind {
      return index
    }
    index = index + 1
  }
  0
}

///|
/// 1 トラック分の `stbl` を生成する。
fn Mp4FileMuxer::build_file_stbl(
  _self : Mp4FileMuxer,
  track : FileTrackEntry,
) -> @boxes.StblBox raise MuxError {
  let stts_entries : Array[@boxes.SttsEntry] = []
  let ctts_entries : Array[@boxes.CttsEntry] = []
  let stsc_entries : Array[@boxes.StscEntry] = []
  let sizes : Array[UInt32] = []
  let offsets : Array[UInt64] = []
  let keyframes : Array[@bytes.NonZeroU32] = []
  let mut sample_number : UInt32 = 1U
  let mut has_cto = false
  let mut has_negative = false
  let mut all_keyframes = true
  let mut chunk_index = 0
  for chunk in track.chunks {
    stsc_entries.push(
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::new((chunk_index + 1).reinterpret_as_uint()).unwrap(),
        chunk.samples.length().reinterpret_as_uint(),
        @bytes.NonZeroU32::new(chunk.sample_entry_index).unwrap(),
      ),
    )
    offsets.push(chunk.data_offset)
    for sample in chunk.samples {
      sizes.push(sample.size)
      if sample.keyframe {
        keyframes.push(@bytes.NonZeroU32::new(sample_number).unwrap())
      } else {
        all_keyframes = false
      }
      match sample.composition_time_offset {
        Some(cto) => {
          has_cto = true
          if cto < 0L {
            has_negative = true
          }
        }
        None => ()
      }
      sample_number = sample_number + 1U
    }
    chunk_index = chunk_index + 1
  }
  // stts / ctts は同じ値の連続をまとめる。
  let all_samples : Array[FileSample] = []
  for chunk in track.chunks {
    for sample in chunk.samples {
      all_samples.push(sample)
    }
  }
  if all_samples.length() > 0 {
    let mut run_count = 1U
    let mut run_delta = all_samples[0].duration
    let mut index = 1
    while index < all_samples.length() {
      if all_samples[index].duration == run_delta {
        run_count = run_count + 1U
      } else {
        stts_entries.push(@boxes.SttsEntry::new(run_count, run_delta))
        run_count = 1U
        run_delta = all_samples[index].duration
      }
      index = index + 1
    }
    stts_entries.push(@boxes.SttsEntry::new(run_count, run_delta))
  }
  if has_cto {
    let mut run_count = 1U
    let mut run_offset = all_samples[0].composition_time_offset.unwrap_or(0L)
    let mut index = 1
    while index < all_samples.length() {
      let offset = all_samples[index].composition_time_offset.unwrap_or(0L)
      if offset == run_offset {
        run_count = run_count + 1U
      } else {
        ctts_entries.push(@boxes.CttsEntry::new(run_count, run_offset))
        run_count = 1U
        run_offset = offset
      }
      index = index + 1
    }
    ctts_entries.push(@boxes.CttsEntry::new(run_count, run_offset))
  }
  let stss = if all_keyframes {
    None
  } else if track.track_kind == @bytes.TrackKind::Video {
    if keyframes.length() == 0 {
      raise MuxError::NoSyncSamples(track_kind=track.track_kind)
    }
    Some(@boxes.StssBox::new(keyframes))
  } else {
    None
  }
  let stsz = @boxes.StszBox::Variable(entry_sizes=sizes)
  let stco = if offsets.length() == 0 {
    @bytes.Either::A(@boxes.StcoBox::new([]))
  } else if offsets[offsets.length() - 1] > 0xFFFFFFFFUL {
    @bytes.Either::B(@boxes.Co64Box::new(offsets))
  } else {
    let offsets32 : Array[UInt32] = []
    for offset in offsets {
      offsets32.push(offset.to_uint())
    }
    @bytes.Either::A(@boxes.StcoBox::new(offsets32))
  }
  @boxes.StblBox::new(
    @boxes.StsdBox::new(track.sample_entries),
    @boxes.SttsBox::new(stts_entries),
    if has_cto {
      Some(
        @boxes.CttsBox::new(if has_negative { 1U } else { 0U }, ctts_entries),
      )
    } else {
      None
    },
    None,
    @boxes.StscBox::new(stsc_entries),
    stsz,
    stco,
    stss,
    None,
    [],
  )
}

///|
/// トラックごとのサンプル数から moov の最大サイズを見積もる。
pub fn estimate_maximum_moov_box_size(
  sample_count_per_track : Array[Int32],
) -> UInt64 {
  let base : UInt64 = 512UL
  let per_track : UInt64 = 1024UL
  let bytes_per_sample : UInt64 = 16UL
  let mut total = base
  total = total + per_track * sample_count_per_track.length().to_uint64()
  for count in sample_count_per_track {
    total = total + bytes_per_sample * count.to_uint64()
  }
  total
}
