///|
/// fMP4 segment muxer のオプション。
pub struct SegmentMuxerOptions {
  /// ファイル作成時刻（UNIX 秒）
  creation_timestamp : UInt64
  /// 音声・映像・字幕のトラックメタデータ
  tracks : TrackMetadataOptions
} derive(Eq, Hash, Debug)

///|
pub extend SegmentMuxerOptions with Eq::{equal, not_equal}

///|
pub extend SegmentMuxerOptions with Hash::{hash, hash_combine}

///|
pub extend SegmentMuxerOptions with Debug::{to_repr}

///|
/// 既定のオプション。
pub fn SegmentMuxerOptions::default() -> SegmentMuxerOptions {
  { creation_timestamp: 0UL, tracks: TrackMetadataOptions::default(), }
}

///|
/// トラックごとの状態。
priv struct SegmentTrackEntry {
  track_kind : @bytes.TrackKind
  timescale : @bytes.NonZeroU32
  sample_entries : Array[@boxes.SampleEntry]
  track_id : UInt32
  mut decode_time : UInt64
  mut current_sample_entry_index : UInt32?
}

///|
/// 1 セグメント分の tfra エントリー。
priv struct TfraSegmentEntry {
  time : UInt64
  moof_relative_offset : UInt64
  traf_number : UInt32
}

///|
/// 解決済みの 1 トラック分のセグメント情報。
priv struct ResolvedSegmentTrack {
  track_index : Int32
  samples : Array[@boxes.TrunSample]
  total_duration : UInt64
  sample_description_index : UInt32?
  first_data_offset : UInt64
  payload_end : UInt64
}

///|
/// fMP4 の init segment と media segment を生成する muxer。
pub struct Fmp4SegmentMuxer {
  priv mut tracks : Array[SegmentTrackEntry]
  priv options : SegmentMuxerOptions
  priv mut sequence_number : UInt32
  priv mut media_bytes_written : UInt64
  priv mut tfra_entries : Array[Array[TfraSegmentEntry]]
}

///|
/// `mdat` のボックス種別。
fn mux_mdat_type() -> @bytes.BoxType {
  @bytes.BoxType::Normal(mux_brand("mdat"))
}

///|
/// 4 バイトブランドを作る。
fn mux_brand(value : String) -> @bytes.FourCC {
  @bytes.FourCC::from_string(value) catch {
    _ => abort("brand must be exactly 4 ASCII bytes")
  }
}

///|
/// 新しい muxer を作る。
pub fn Fmp4SegmentMuxer::new() -> Fmp4SegmentMuxer {
  Fmp4SegmentMuxer::with_options(SegmentMuxerOptions::default())
}

///|
/// オプションを指定して muxer を作る。
pub fn Fmp4SegmentMuxer::with_options(
  options : SegmentMuxerOptions,
) -> Fmp4SegmentMuxer {
  {
    tracks: [],
    options,
    sequence_number: 0U,
    media_bytes_written: 0UL,
    tfra_entries: [],
  }
}

///|
/// 初期化セグメント（`ftyp` + `moov`）を返す。
pub fn Fmp4SegmentMuxer::init_segment_bytes(
  self : Fmp4SegmentMuxer,
) -> Bytes raise MuxError {
  if self.tracks.length() == 0 {
    raise MuxError::EmptyTracks
  }
  let ftyp = self.build_ftyp()
  let moov = self.build_init_moov()
  let ftyp_bytes = wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(ftyp)
  })
  let moov_bytes = wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(moov)
  })
  ftyp_bytes + moov_bytes
}

///|
/// `ftyp` を生成する。
fn Fmp4SegmentMuxer::build_ftyp(self : Fmp4SegmentMuxer) -> @boxes.FtypBox {
  let brands = [mux_brand("iso5"), mux_brand("iso6"), mux_brand("mp41")]
  for track in self.tracks {
    for entry in track.sample_entries {
      let code : String = match entry {
        @boxes.SampleEntry::Hev1(_) => "hev1"
        @boxes.SampleEntry::Hvc1(_) => "hvc1"
        @boxes.SampleEntry::Av01(_) => "av01"
        _ => ""
      }
      if code != "" && !brands.contains(mux_brand(code)) {
        brands.push(mux_brand(code))
      }
    }
  }
  @boxes.FtypBox::new(mux_brand("iso5"), 0U, brands)
}

///|
/// init segment の `moov` を生成する。
fn Fmp4SegmentMuxer::build_init_moov(self : Fmp4SegmentMuxer) -> @boxes.MoovBox {
  let time = @bytes.Mp4FileTime::from_unix_seconds(
    self.options.creation_timestamp,
  )
  let traks : Array[@boxes.TrakBox] = []
  for track in self.tracks {
    traks.push(self.build_init_trak(track, time))
  }
  let trex_boxes : Array[@boxes.TrexBox] = []
  for track in self.tracks {
    trex_boxes.push(
      @boxes.TrexBox::new(
        track.track_id,
        1U,
        0U,
        0U,
        @boxes.SampleFlags::empty(),
      ),
    )
  }
  let mvex = @boxes.MvexBox::new(Some(@boxes.MehdBox::new(0UL)), trex_boxes, [])
  let mvhd = @boxes.MvhdBox::new(
    time,
    time,
    @bytes.NonZeroU32::new(1000U).unwrap(),
    0UL,
    @boxes.MvhdBox::default_rate(),
    @boxes.MvhdBox::default_volume(),
    @boxes.MvhdBox::default_matrix(),
    (self.tracks.length() + 1).reinterpret_as_uint(),
  )
  @boxes.MoovBox::with_mvex(mvhd, traks, mvex, [])
}

///|
/// init segment の `trak` を生成する。
fn Fmp4SegmentMuxer::build_init_trak(
  self : Fmp4SegmentMuxer,
  track : SegmentTrackEntry,
  time : @bytes.Mp4FileTime,
) -> @boxes.TrakBox {
  let entry = match track.sample_entries[0] {
    _ => track.sample_entries[0]
  }
  let (volume, width, height, handler, media_header) = match track.track_kind {
    @bytes.TrackKind::Video => {
      let (w, h) = match entry.video_resolution() {
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
      let (handler, media_header) = subtitle_trak_attributes(entry)
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
    track.track_id,
    0UL,
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
    0UL,
    metadata.language,
  )
  let stbl = @boxes.StblBox::new(
    @boxes.StsdBox::new(track.sample_entries),
    @boxes.SttsBox::new([]),
    None,
    None,
    @boxes.StscBox::new([]),
    @boxes.StszBox::Variable(entry_sizes=[]),
    @bytes.Either::A(@boxes.StcoBox::new([])),
    None,
    None,
    [],
  )
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
/// 字幕 sample entry から handler と media header を決める。
fn subtitle_trak_attributes(
  entry : @boxes.SampleEntry,
) -> (@bytes.FourCC, @boxes.MediaHeader) {
  match entry {
    _ =>
      (
        @boxes.HdlrBox::handler_type_subt(),
        @boxes.MediaHeader::Sthd(@boxes.SthdBox::new()),
      )
  }
}

///|
/// メディアセグメントの metadata（`moof` + `mdat` ヘッダー）を生成する。
pub fn Fmp4SegmentMuxer::create_media_segment_metadata(
  self : Fmp4SegmentMuxer,
  samples : Array[Sample],
) -> Bytes raise MuxError {
  let (segment, _payload_size) = self.build_media_segment(samples)
  segment
}

///|
/// `sidx` 付きのメディアセグメント metadata を生成する。
pub fn Fmp4SegmentMuxer::create_media_segment_metadata_with_sidx(
  self : Fmp4SegmentMuxer,
  samples : Array[Sample],
) -> Bytes raise MuxError {
  if samples.length() == 0 {
    raise MuxError::EmptySamples
  }
  let first_kind = samples[0].track_kind
  let track = self.find_track(first_kind) catch {
    _ => raise MuxError::EmptyTracks
  }
  let mut subsegment_duration : UInt64 = 0UL
  let mut decode_time : UInt64 = 0UL
  for t in self.tracks {
    if t.track_kind == first_kind {
      decode_time = t.decode_time
    }
  }
  let mut min_pts : Int64? = None
  let mut sap_at_ept = false
  let mut dts = decode_time
  for sample in samples {
    if sample.track_kind == first_kind {
      subsegment_duration = subsegment_duration + sample.duration.to_uint64()
      let pts = dts.reinterpret_as_int64() +
        sample.composition_time_offset.unwrap_or(0L)
      let replace = match min_pts {
        Some(current) => pts < current
        None => true
      }
      if replace {
        min_pts = Some(pts)
        sap_at_ept = sample.keyframe
      }
      dts = dts + sample.duration.to_uint64()
    }
  }
  let ept = match min_pts {
    Some(pts) => {
      if pts < 0L {
        raise MuxError::Overflow
      }
      pts.reinterpret_as_uint64()
    }
    None => 0UL
  }
  let pre_tfra_lengths : Array[Int32] = []
  for entries in self.tfra_entries {
    pre_tfra_lengths.push(entries.length())
  }
  let (segment, payload_size) = self.build_media_segment(samples)
  let media_size = segment.length() + payload_size.to_int()
  let referenced_size = if media_size > 0xFFFFFFFF {
    raise MuxError::Overflow
  } else {
    media_size.reinterpret_as_uint()
  }
  let sidx = @boxes.SidxBox::new(
    track.track_id,
    track.timescale.get(),
    ept,
    0UL,
    [
      @boxes.SidxReference::new(
        false,
        referenced_size,
        subsegment_duration.to_uint(),
        sap_at_ept,
        if sap_at_ept {
          1U
        } else {
          0U
        },
        0U,
      ),
    ],
  )
  let sidx_bytes = wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(sidx)
  })
  let sidx_size = sidx_bytes.length().to_uint64()
  // sidx を先頭に置くため、今回追加された tfra エントリーの moof 位置をずらす。
  let mut track_index = 0
  while track_index < self.tfra_entries.length() {
    let entries = self.tfra_entries[track_index]
    let pre = if track_index < pre_tfra_lengths.length() {
      pre_tfra_lengths[track_index]
    } else {
      0
    }
    if entries.length() > pre {
      let last = entries.length() - 1
      entries[last] = {
        time: entries[last].time,
        moof_relative_offset: entries[last].moof_relative_offset + sidx_size,
        traf_number: entries[last].traf_number,
      }
    }
    track_index = track_index + 1
  }
  self.media_bytes_written = self.media_bytes_written + sidx_size
  sidx_bytes + segment
}

///|
/// `mfra` を生成する。
pub fn Fmp4SegmentMuxer::mfra_bytes(
  self : Fmp4SegmentMuxer,
) -> Bytes raise MuxError {
  let init_size = self.init_segment_bytes().length().to_uint64()
  let tfra_boxes : Array[@boxes.TfraBox] = []
  let mut track_index = 0
  while track_index < self.tfra_entries.length() {
    let entries = self.tfra_entries[track_index]
    if entries.length() > 0 && track_index < self.tracks.length() {
      let track = self.tracks[track_index]
      let tfra_entries : Array[@boxes.TfraEntry] = []
      let mut needs_v1 = false
      let mut max_traf : UInt32 = 0U
      for e in entries {
        let moof_offset = init_size + e.moof_relative_offset
        if e.time > 0xFFFFFFFFUL || moof_offset > 0xFFFFFFFFUL {
          needs_v1 = true
        }
        if e.traf_number > max_traf {
          max_traf = e.traf_number
        }
        tfra_entries.push(
          @boxes.TfraEntry::new(e.time, moof_offset, e.traf_number, 1U, 1U),
        )
      }
      let length_size_of_traf_num = if max_traf <= 0xFFU {
        0U
      } else if max_traf <= 0xFFFFU {
        1U
      } else if max_traf <= 0xFFFFFFU {
        2U
      } else {
        3U
      }
      tfra_boxes.push(
        @boxes.TfraBox::new(
          if needs_v1 {
            1U
          } else {
            0U
          },
          track.track_id,
          length_size_of_traf_num,
          0U,
          0U,
          tfra_entries,
        ),
      )
    }
    track_index = track_index + 1
  }
  let placeholder = wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(
      @boxes.MfraBox::new(tfra_boxes, @boxes.MfroBox::new(0U)),
    )
  })
  let size = placeholder.length().reinterpret_as_uint()
  wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(
      @boxes.MfraBox::new(tfra_boxes, @boxes.MfroBox::new(size)),
    )
  })
}

///|
/// `track_kind` のトラックを探す。
fn Fmp4SegmentMuxer::find_track(
  self : Fmp4SegmentMuxer,
  kind : @bytes.TrackKind,
) -> SegmentTrackEntry raise MuxError {
  for track in self.tracks {
    if track.track_kind == kind {
      return track
    }
  }
  raise MuxError::EmptyTracks
}

///|
/// メディアセグメントを構築し、`(metadata bytes, mdat payload size)` を返す。
fn Fmp4SegmentMuxer::build_media_segment(
  self : Fmp4SegmentMuxer,
  samples : Array[Sample],
) -> (Bytes, UInt64) raise MuxError {
  if samples.length() == 0 {
    raise MuxError::EmptySamples
  }
  let sequence = if self.sequence_number == 0xFFFFFFFFU {
    raise MuxError::Overflow
  } else {
    self.sequence_number + 1U
  }
  // 失敗時に状態を変えないよう、トラック状態を複製してから解決する。
  let next_tracks : Array[SegmentTrackEntry] = []
  for track in self.tracks {
    let entries : Array[@boxes.SampleEntry] = []
    for entry in track.sample_entries {
      entries.push(entry)
    }
    next_tracks.push({
      track_kind: track.track_kind,
      timescale: track.timescale,
      sample_entries: entries,
      track_id: track.track_id,
      decode_time: track.decode_time,
      current_sample_entry_index: track.current_sample_entry_index,
    })
  }
  let resolved = self.resolve_segment_tracks(next_tracks, samples)
  let mut mdat_payload_size : UInt64 = 0UL
  for track in resolved {
    if track.payload_end > mdat_payload_size {
      mdat_payload_size = track.payload_end
    }
  }
  let mdat_box_size = mdat_payload_size + 8UL
  let (mdat_header_bytes, mdat_header_size) = if mdat_box_size <= 0xFFFFFFFFUL {
    (
      wrap_mux_encode(fn() raise @bytes.Mp4Error {
        @bytes.encode_to_bytes(
          @box.BoxHeader::new(
            mux_mdat_type(),
            @box.BoxSize::U32(mdat_box_size.to_uint()),
          ),
        )
      }),
      8,
    )
  } else {
    (
      wrap_mux_encode(fn() raise @bytes.Mp4Error {
        @bytes.encode_to_bytes(
          @box.BoxHeader::new(
            mux_mdat_type(),
            @box.BoxSize::U64(mdat_payload_size + 16UL),
          ),
        )
      }),
      16,
    )
  }
  // data_offset は固定長なので、0 で一度エンコードして moof のサイズを確定する。
  let placeholder_offsets : Array[Int32] = []
  for _ in resolved {
    placeholder_offsets.push(0)
  }
  let placeholder_moof = self.build_moof(
    next_tracks, resolved, sequence, placeholder_offsets,
  )
  let placeholder_bytes = wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(placeholder_moof)
  })
  let moof_size = placeholder_bytes.length().to_uint64()
  let data_offset_base = moof_size + mdat_header_size.to_uint64()
  let data_offsets : Array[Int32] = []
  for _ in next_tracks {
    data_offsets.push(0)
  }
  for track in resolved {
    let offset = data_offset_base + track.first_data_offset
    if offset > 0x7FFFFFFFUL {
      raise MuxError::Overflow
    }
    data_offsets[track.track_index] = offset.to_int()
  }
  let moof = self.build_moof(next_tracks, resolved, sequence, data_offsets)
  let moof_bytes = wrap_mux_encode(fn() raise @bytes.Mp4Error {
    @bytes.encode_to_bytes(moof)
  })
  let segment = moof_bytes + mdat_header_bytes

  // tfra エントリーを追加する。
  let next_tfra : Array[Array[TfraSegmentEntry]] = []
  let mut ti = 0
  while ti < next_tracks.length() {
    let entries : Array[TfraSegmentEntry] = []
    if ti < self.tfra_entries.length() {
      for e in self.tfra_entries[ti] {
        entries.push(e)
      }
    }
    next_tfra.push(entries)
    ti = ti + 1
  }
  let mut traf_pos = 0
  for track in resolved {
    let idx = track.track_index
    next_tfra[idx].push({
      time: next_tracks[idx].decode_time,
      moof_relative_offset: self.media_bytes_written,
      traf_number: (traf_pos + 1).reinterpret_as_uint(),
    })
    traf_pos = traf_pos + 1
  }
  for track in resolved {
    let idx = track.track_index
    next_tracks[idx].decode_time = next_tracks[idx].decode_time +
      track.total_duration
  }
  self.tracks = next_tracks
  self.tfra_entries = next_tfra
  self.sequence_number = sequence
  self.media_bytes_written = self.media_bytes_written +
    segment.length().to_uint64() +
    mdat_payload_size
  (segment, mdat_payload_size)
}

///|
/// サンプル列をトラックごとに解決する。
fn Fmp4SegmentMuxer::resolve_segment_tracks(
  self : Fmp4SegmentMuxer,
  tracks : Array[SegmentTrackEntry],
  samples : Array[Sample],
) -> Array[ResolvedSegmentTrack] raise MuxError {
  let kinds : Array[@bytes.TrackKind] = []
  for sample in samples {
    let mut found = false
    for kind in kinds {
      if kind == sample.track_kind {
        found = true
      }
    }
    if !found {
      kinds.push(sample.track_kind)
    }
  }
  let resolved : Array[ResolvedSegmentTrack] = []
  for kind in kinds {
    let track_samples : Array[Sample] = []
    for sample in samples {
      if sample.track_kind == kind {
        track_samples.push(sample)
      }
    }
    let first = track_samples[0]
    let track_index = self.ensure_track(tracks, kind, first.timescale)
    let track = tracks[track_index]
    let mut current_index = track.current_sample_entry_index
    let mut segment_index : UInt32? = None
    let mut total_duration : UInt64 = 0UL
    let mut expected_offset : UInt64? = None
    let mut first_data_offset : UInt64 = 0UL
    let mut payload_end : UInt64 = 0UL
    let trun_samples : Array[@boxes.TrunSample] = []
    for sample in track_samples {
      if sample.timescale != track.timescale {
        raise MuxError::TimescaleMismatch(
          track_kind=kind,
          expected=track.timescale,
          actual=sample.timescale,
        )
      }
      let entry_index = match sample.sample_entry {
        Some(entry) => {
          let mut found : Int32? = None
          let mut i = 0
          while i < track.sample_entries.length() {
            if track.sample_entries[i] == entry {
              found = Some(i)
            }
            i = i + 1
          }
          match found {
            Some(index) => index
            None => {
              track.sample_entries.push(entry)
              track.sample_entries.length() - 1
            }
          }
        }
        None =>
          match current_index {
            Some(index) => index.reinterpret_as_int()
            None => raise MuxError::MissingSampleEntry(track_kind=kind)
          }
      }
      let entry_index_u32 = entry_index.reinterpret_as_uint() + 1U
      match segment_index {
        Some(expected) =>
          if expected != entry_index_u32 {
            raise MuxError::MixedSampleEntries(track_kind=kind)
          }
        None => segment_index = Some(entry_index_u32)
      }
      current_index = Some(entry_index.reinterpret_as_uint())
      total_duration = total_duration + sample.duration.to_uint64()
      if expected_offset is None {
        first_data_offset = sample.data_offset
      }
      match expected_offset {
        Some(expected) =>
          if expected != sample.data_offset {
            raise MuxError::EncodeError(
              @bytes.Mp4Error::invalid_input(
                "sample data for the same track must be contiguous in the segment payload",
              ),
            )
          }
        None => ()
      }
      expected_offset = Some(sample.data_offset + sample.data_size.to_uint64())
      payload_end = sample.data_offset + sample.data_size.to_uint64()
      let flags = if sample.keyframe {
        @boxes.SampleFlags::from_fields(0, 2, 0, 0, 0, false, 0)
      } else {
        @boxes.SampleFlags::from_fields(0, 1, 0, 0, 0, true, 0)
      }
      trun_samples.push(
        @boxes.TrunSample::new(
          Some(sample.duration),
          Some(sample.data_size),
          Some(flags),
          sample.composition_time_offset,
        ),
      )
    }
    track.current_sample_entry_index = current_index
    let sample_description_index = match segment_index {
      Some(index) if index == 1U => None
      Some(index) => Some(index)
      None => None
    }
    resolved.push({
      track_index,
      samples: trun_samples,
      total_duration,
      sample_description_index,
      first_data_offset,
      payload_end,
    })
  }
  resolved.sort_by(fn(a, b) {
    if a.first_data_offset < b.first_data_offset {
      -1
    } else if a.first_data_offset > b.first_data_offset {
      1
    } else {
      0
    }
  })
  let mut expected : UInt64 = 0UL
  for track in resolved {
    if track.first_data_offset != expected {
      raise MuxError::EncodeError(
        @bytes.Mp4Error::invalid_input(
          "track payload ranges must be contiguous and ordered by data_offset",
        ),
      )
    }
    expected = track.payload_end
  }
  resolved
}

///|
/// `track_kind` のトラックを取得または追加する。
fn Fmp4SegmentMuxer::ensure_track(
  _self : Fmp4SegmentMuxer,
  tracks : Array[SegmentTrackEntry],
  kind : @bytes.TrackKind,
  timescale : @bytes.NonZeroU32,
) -> Int32 raise MuxError {
  let mut index = 0
  while index < tracks.length() {
    if tracks[index].track_kind == kind {
      if tracks[index].timescale != timescale {
        raise MuxError::TimescaleMismatch(
          track_kind=kind,
          expected=tracks[index].timescale,
          actual=timescale,
        )
      }
      return index
    }
    index = index + 1
  }
  let track_id = (tracks.length() + 1).reinterpret_as_uint()
  tracks.push({
    track_kind: kind,
    timescale,
    sample_entries: [],
    track_id,
    decode_time: 0UL,
    current_sample_entry_index: None,
  })
  tracks.length() - 1
}

///|
/// `moof` を構築する。
fn Fmp4SegmentMuxer::build_moof(
  _self : Fmp4SegmentMuxer,
  tracks : Array[SegmentTrackEntry],
  resolved : Array[ResolvedSegmentTrack],
  sequence : UInt32,
  data_offsets : Array[Int32],
) -> @boxes.MoofBox {
  let trafs : Array[@boxes.TrafBox] = []
  for track in resolved {
    let entry = tracks[track.track_index]
    let trun = @boxes.TrunBox::new(
      Some(data_offsets[track.track_index]),
      None,
      track.samples,
    )
    let tfhd = @boxes.TfhdBox::new(
      entry.track_id,
      None,
      track.sample_description_index,
      None,
      None,
      None,
      false,
      true,
    )
    let tfdt = @boxes.TfdtBox::new(
      if entry.decode_time > 0xFFFFFFFFUL {
        1U
      } else {
        0U
      },
      entry.decode_time,
    )
    trafs.push(@boxes.TrafBox::new(tfhd, Some(tfdt), [trun], []))
  }
  @boxes.MoofBox::new(@boxes.MfhdBox::new(sequence), trafs, [])
}
