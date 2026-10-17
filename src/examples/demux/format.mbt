// demux CLI の出力整形。
// テキスト出力は upstream の examples/demux.rs に近い人間可読形式、
// JSON 出力は本リポジトリのデータ契約 (64bit 整数は十進文字列) に従う。

///|
/// TrackKind の表示名 (upstream の `{:?}` 相当の小文字表現)。
fn track_kind_name(kind : @bytes.TrackKind) -> String {
  match kind {
    Video => "video"
    Audio => "audio"
    Subtitle => "subtitle"
  }
}

///|
/// TrackInfo をテキスト行として整形する (upstream demux.rs 相当 + Kind 列)。
fn format_track_text(index : Int32, track : @mp4_demux.TrackInfo) -> String {
  let track_id = track.track_id
  let kind = track_kind_name(track.kind)
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
/// TrackInfo の JSON 表現。`duration` (u64) は十進文字列。
fn track_json(index : Int32, track : @mp4_demux.TrackInfo) -> Json {
  {
    "index": index,
    "track_id": track.track_id,
    "kind": Json(track_kind_name(track.kind)),
    "duration": track.duration.to_string(),
    "timescale": track.timescale.get(),
  }
}

///|
/// Sample の JSON 表現。
/// `timestamp` / `composition_time_offset` / `data_offset` (u64/i64) は十進文字列、
/// `sample_entry` は新しいエントリに切り替わったサンプルでのみ 4CC 文字列。
fn sample_json(index : Int32, sample : @mp4_demux.Sample) -> Json {
  let sample_entry : Json = match sample.sample_entry {
    Some(entry) => Json(entry.box_type().to_string())
    None => null
  }
  let cto : Json = match sample.composition_time_offset {
    Some(offset) => Json(offset.to_string())
    None => null
  }
  {
    "index": index,
    "track_id": sample.track.track_id,
    "sample_entry": sample_entry,
    "keyframe": sample.keyframe,
    "timestamp": sample.timestamp.to_string(),
    "duration": sample.duration,
    "composition_time_offset": cto,
    "data_offset": sample.data_offset.to_string(),
    "data_size": sample.data_size,
  }
}

///|
/// JSON 出力全体。64bit 値はすべて十進文字列で出力する。
fn format_json(
  file~ : String,
  tracks : ArrayView[@mp4_demux.TrackInfo],
  samples : ArrayView[@mp4_demux.Sample],
  truncated~ : Bool,
) -> String {
  let track_items : Array[Json] = []
  for i, track in tracks {
    track_items.push(track_json(i, track))
  }
  let sample_items : Array[Json] = []
  for i, sample in samples {
    sample_items.push(sample_json(i, sample))
  }
  let doc : Json = {
    "file": file,
    "tracks": track_items,
    "samples": sample_items,
    "shown_samples": samples.length(),
    "truncated": truncated,
  }
  doc.stringify(indent=2) + "\n"
}
