///|
/// `demux-cases` が生成するケース 1 件分（生成データ用）。
///
/// `requests` は上流デマルチプレクサが順に要求した入力範囲の列で、
/// `mdat` のようなペイロードを読み飛ばしていることをそのまま証明する。
priv struct OracleDemuxCase {
  name : String
  input : Bytes
  requests : Array[OracleDemuxRequest]
  tracks : Array[String]
  tracks_error : String
  samples : Array[String]
  samples_error : String
  prev_samples : Array[String]
  prev_error : String
  seek_probes : Array[OracleDemuxSeekProbe]
}

///|
/// oracle が記録した必須入力範囲 1 件分。
priv struct OracleDemuxRequest {
  position : UInt64
  size : UInt64?
}

///|
/// oracle のシークプローブ 1 件分（`secs` 秒 + `nanos` でシークした直後の
/// `next_sample` の凍結行、または `"none"` / `"error:..."`）。
priv struct OracleDemuxSeekProbe {
  secs : UInt64
  nanos : UInt32
  expected : String
}

///|
/// oracle の `required_slice` に対応する。
/// 要求された範囲だけを（EOF で切り詰めて）供給する。
fn demux_slice_at(
  data : Bytes,
  required : @demux.RequiredInput,
) -> @demux.Input {
  let len = data.length().to_uint64()
  let start = if required.position > len { len } else { required.position }
  let end = match required.size {
    Some(size) => {
      let wanted = start + size
      if wanted > len {
        len
      } else {
        wanted
      }
    }
    None => len
  }
  @demux.Input::{ position: start, data: data[start.to_int():end.to_int()], }
}

///|
/// oracle の `demux_error_line` に対応する凍結行を組み立てる。
fn demux_error_line(error : @demux.DemuxError) -> String {
  match error {
    @demux.DecodeError(e) => {
      let @bytes.Mp4Error(kind~, reason~, box_type~, ..) = e
      let box_type_str = match box_type {
        Some(t) => t.to_string()
        None => ""
      }
      // 上流の `insufficient_buffer` は常に reason が空なので、
      // MoonBit 側の診断メッセージ差分はここで正規化する
      let reason_str = match kind {
        InsufficientBuffer => ""
        _ => reason.to_string()
      }
      "classification=decode_error,error_kind=\{oracle_kind_name(kind)},box_type=\{box_type_str},reason=\{reason_str}"
    }
    @demux.SampleTableError(e) =>
      "classification=sample_table_error,reason=\{e.to_string()}"
    @demux.InvalidState(message) =>
      "classification=invalid_state,reason=\{message}"
    @demux.InputRequired(required) => {
      let size_str = match required.size {
        Some(size) => "\{size}"
        None => "none"
      }
      "classification=input_required,position=\{required.position},size=\{size_str}"
    }
  }
}

///|
/// oracle の `demux_track_line` に対応する凍結行を組み立てる。
fn demux_track_line(track : @demux.TrackInfo) -> String {
  let kind_str = match track.kind {
    @bytes.TrackKind::Video => "video"
    @bytes.TrackKind::Audio => "audio"
    @bytes.TrackKind::Subtitle => "subtitle"
  }
  "track_id=\{track.track_id},kind=\{kind_str},duration=\{track.duration},timescale=\{track.timescale.get()}"
}

///|
/// oracle の `demux_sample_line` に対応する凍結行を組み立てる。
fn demux_sample_line(sample : @demux.Sample) -> String {
  let entry_str = match sample.sample_entry {
    Some(entry) => entry.box_type().to_string()
    None => "none"
  }
  let cto_str = match sample.composition_time_offset {
    Some(offset) => "\{offset}"
    None => "none"
  }
  "track_id=\{sample.track.track_id},sample_entry=\{entry_str},keyframe=\{sample.keyframe},dts=\{sample.timestamp},duration=\{sample.duration},pts_offset=\{cto_str},data_offset=\{sample.data_offset},data_size=\{sample.data_size}"
}

///|
/// `next_sample` / `prev_sample` の呼び出しを `Result` に写すヘルパー。
fn next_sample_result(
  demuxer : @demux.Mp4FileDemuxer,
) -> Result[@demux.Sample?, @demux.DemuxError] {
  try Ok(demuxer.next_sample()) catch {
    e => Err(e)
  } noraise {
    v => v
  }
}

///|
fn prev_sample_result(
  demuxer : @demux.Mp4FileDemuxer,
) -> Result[@demux.Sample?, @demux.DemuxError] {
  try Ok(demuxer.prev_sample()) catch {
    e => Err(e)
  } noraise {
    v => v
  }
}

///|
fn seek_result(
  demuxer : @demux.Mp4FileDemuxer,
  position : @demux.Duration,
) -> Result[Unit, @demux.DemuxError] {
  try Ok(demuxer.seek(position)) catch {
    e => Err(e)
  } noraise {
    v => v
  }
}

///|
/// oracle の `drive_demux_case` に対応する。
///
/// 要求範囲だけを供給して初期化し、トラック一覧・前方サンプル列・
/// 後方サンプル列・シークプローブの観測結果を返す。
fn drive_demux_case(
  case : OracleDemuxCase,
) -> (
  Array[@demux.RequiredInput],
  Array[String],
  String,
  Array[String],
  String,
  Array[String],
  String,
  Array[String],
) {
  let demuxer = @demux.Mp4FileDemuxer::new()
  let requests : Array[@demux.RequiredInput] = []
  for _ in 0..<10000 {
    match demuxer.required_input() {
      Some(required) => {
        requests.push(required)
        demuxer.handle_input(demux_slice_at(case.input, required))
      }
      None => break
    }
  }
  let (tracks, tracks_error) = try demuxer.tracks() catch {
    e => ([], demux_error_line(e))
  } noraise {
    found => (found.iter().map(demux_track_line).collect(), "")
  }
  let samples : Array[String] = []
  let mut samples_error = ""
  let mut samples_done = false
  while !samples_done {
    if samples.length() >= 100000 {
      samples_error = "classification=input_required,reason=sample enumeration did not terminate"
      break
    }
    match next_sample_result(demuxer) {
      Ok(Some(sample)) => samples.push(demux_sample_line(sample))
      Ok(None) => samples_done = true
      Err(e) => {
        samples_error = demux_error_line(e)
        samples_done = true
      }
    }
  }
  let prev_samples : Array[String] = []
  let mut prev_error = ""
  let mut prev_done = false
  while !prev_done {
    if prev_samples.length() >= 100000 {
      prev_error = "classification=input_required,reason=sample enumeration did not terminate"
      break
    }
    match prev_sample_result(demuxer) {
      Ok(Some(sample)) => prev_samples.push(demux_sample_line(sample))
      Ok(None) => prev_done = true
      Err(e) => {
        prev_error = demux_error_line(e)
        prev_done = true
      }
    }
  }
  let seek_results : Array[String] = []
  for probe in case.seek_probes {
    let expected = match @demux.Duration::new(probe.secs, probe.nanos) {
      None => "error:duration out of range"
      Some(position) =>
        match seek_result(demuxer, position) {
          Err(e) => "error:\{demux_error_line(e)}"
          Ok(_) =>
            match next_sample_result(demuxer) {
              Ok(Some(sample)) => demux_sample_line(sample)
              Ok(None) => "none"
              Err(e) => "error:\{demux_error_line(e)}"
            }
        }
    }
    seek_results.push(expected)
  }
  (
    requests, tracks, tracks_error, samples, samples_error, prev_samples, prev_error,
    seek_results,
  )
}

///|
test "mp4 file demuxer matches the rust oracle" {
  inspect(oracle_demux_cases.length() > 0, content="true")
  for case in oracle_demux_cases {
    if case.name == "" {
      abort("oracle emitted a case without a name")
    }
    let (
      requests,
      tracks,
      tracks_error,
      samples,
      samples_error,
      prev_samples,
      prev_error,
      seek_results,
    ) = drive_demux_case(case)

    // 要求範囲の列が上流と一致すること（mdat のペイロードを要求しない証拠）
    assert_eq(requests.length(), case.requests.length())
    for i, req in requests.iter2() {
      assert_eq(req.position, case.requests[i].position)
      assert_eq(req.size, case.requests[i].size)
    }
    assert_eq(tracks, case.tracks)
    assert_eq(tracks_error, case.tracks_error)
    assert_eq(samples, case.samples)
    assert_eq(samples_error, case.samples_error)
    assert_eq(prev_samples, case.prev_samples)
    assert_eq(prev_error, case.prev_error)
    assert_eq(seek_results.length(), case.seek_probes.length())
    for i, probe in case.seek_probes.iter2() {
      assert_eq(seek_results[i], probe.expected)
    }
  }
}
