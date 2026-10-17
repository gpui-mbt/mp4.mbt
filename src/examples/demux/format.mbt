// demux CLI の出力整形。
// テキスト出力は upstream の examples/demux.rs に近い人間可読形式、
// JSON 出力は src/demux_report の canonical スキーマ (64bit 整数は十進文字列) に従う。

///|
/// TrackInfo をテキスト行として整形する (upstream demux.rs 相当 + Kind 列)。
fn format_track_text(index : Int32, track : @mp4_demux.TrackInfo) -> String {
  let track_id = track.track_id
  let kind = @demux_report.track_kind_name(track.kind)
  let duration = track.duration
  let timescale = track.timescale.get()
  "Track \{index}:\n" +
  "  Track ID: \{track_id}\n" +
  "  Kind: \{kind}\n" +
  "  Duration: \{duration} (timescale: \{timescale})"
}

///|
/// Sample をテキスト行として整形する (upstream demux.rs 相当 + Kind/CTTS/keyframe 列)。
fn format_sample_text(index : Int32, sample : @mp4_demux.Sample) -> String {
  let track_id = sample.track.track_id
  let sample_entry = match sample.sample_entry {
    Some(entry) => entry.box_type().to_string()
    None => "unchanged"
  }
  let keyframe = sample.keyframe
  let timestamp = sample.timestamp
  let duration = sample.duration
  let cto = match sample.composition_time_offset {
    Some(offset) => offset.to_string()
    None => "none"
  }
  let data_offset = sample.data_offset
  let data_size = sample.data_size
  "Sample \{index}:\n" +
  "    Track ID: \{track_id}\n" +
  "    Sample entry: \{sample_entry}\n" +
  "    Keyframe: \{keyframe}\n" +
  "    Timestamp: \{timestamp}\n" +
  "    Duration: \{duration}\n" +
  "    Composition time offset: \{cto}\n" +
  "    Data offset: 0x\{to_hex(data_offset)}\n" +
  "    Data size: \{data_size} bytes"
}

///|
/// UInt64 の 16 進表現 (0x なし・小文字)。upstream の `0x{:x}` 表示用。
fn to_hex(value : UInt64) -> String {
  let table : FixedArray[String] = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
  ]
  if value == 0UL {
    return "0"
  }
  let mut remaining = value
  let mut acc = ""
  while remaining > 0UL {
    let digit = (remaining % 16UL).to_int()
    acc = table[digit] + acc
    remaining = remaining / 16UL
  }
  acc
}

///|
/// テキスト出力全体 (tracks + samples + 打ち切り注記)。
fn format_text(
  tracks : ArrayView[@mp4_demux.TrackInfo],
  samples : ArrayView[@mp4_demux.Sample],
  truncated~ : Bool,
) -> String {
  let out = StringBuilder()
  let count = tracks.length()
  if count == 1 {
    out.write_string("Found 1 track\n\n")
  } else {
    out.write_string("Found \{count} tracks\n\n")
  }
  for i, track in tracks {
    out.write_string(format_track_text(i + 1, track))
    out.write_string("\n\n")
  }
  out.write_string("Samples:\n")
  for i, sample in samples {
    out.write_string("  ")
    out.write_string(format_sample_text(i + 1, sample))
    out.write_string("\n\n")
  }
  if truncated {
    out.write_string("  ... (showing first \{samples.length()} samples)\n")
  }
  out.to_string()
}

///|
/// JSON 出力全体 (canonical スキーマは src/demux_report 側で定義)。
/// `codec` 列には表示済みサンプルから推定した codec 文字列を載せる
/// (サンプルが打ち切りで 1 つも現れなかったトラックは `null`)。
fn format_json(
  file~ : String,
  tracks : ArrayView[@mp4_demux.TrackInfo],
  samples : ArrayView[@mp4_demux.Sample],
  truncated~ : Bool,
) -> String {
  let codec_map = @demux_report.track_codec_map(samples)
  let doc = @demux_report.report_json(
    file~,
    tracks,
    samples,
    truncated~,
    codec_map~,
  )
  @demux_report.report_json_string(doc)
}
