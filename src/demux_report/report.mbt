// demux 結果の canonical JSON 表現。
// CLI (src/examples/demux) と Web デモ (src/webdump) で共有し、
// 64bit 整数は常に十進文字列として出力する。

///|
/// TrackKind の表示名 (upstream の `{:?}` 相当の小文字表現)。
pub fn track_kind_name(kind : @bytes.TrackKind) -> String {
  match kind {
    Video => "video"
    Audio => "audio"
    Subtitle => "subtitle"
  }
}

///|
/// SampleEntry の RFC 6381 codec 文字列を返す。
/// `from_sample_entry` が失敗する場合 (未知のエントリ種別など) は `None`。
fn codec_of_entry(entry : @boxes.SampleEntry) -> String? {
  try @codec_string.from_sample_entry(entry) catch {
    _ => None
  } noraise {
    codec => Some(codec)
  }
}

///|
/// サンプル列からトラック ID ごとの codec 表現を作る。
///
/// 各トラックについて、サンプルに最初に現れた `sample_entry` を codec 推定の
/// 根拠にする。値は次のいずれか:
/// - `"avc1.640028"` のような codec 文字列
/// - `"unsupported"` (エントリはあるが codec 文字列化できない場合)
///
/// サンプルが 1 つも現れなかったトラックはマップに含まれない
/// (呼び出し側では `null` として扱う)。
pub fn track_codec_map(
  samples : ArrayView[@mp4_demux.Sample],
) -> Map[UInt32, Json] {
  let map : Map[UInt32, Json] = Map([])
  for sample in samples {
    let track_id = sample.track.track_id
    if map.get(track_id) is None {
      match sample.sample_entry {
        Some(entry) =>
          map[track_id] = match codec_of_entry(entry) {
            Some(codec) => Json(codec)
            None => Json("unsupported")
          }
        None => ()
      }
    }
  }
  map
}

///|
/// TrackInfo の JSON 表現。`duration` (u64) は十進文字列。
/// `codec` は [`track_codec_map`] の結果をそのまま埋め込む
/// (無い場合は `null`)。
pub fn track_json(
  index : Int32,
  track : @mp4_demux.TrackInfo,
  codec~ : Json = Json::null(),
) -> Json {
  {
    "index": index,
    "track_id": track.track_id,
    "kind": Json(track_kind_name(track.kind)),
    "codec": codec,
    "duration": track.duration.to_string(),
    "timescale": track.timescale.get(),
  }
}

///|
/// Sample の JSON 表現。
/// `timestamp` / `composition_time_offset` / `data_offset` (u64/i64) は十進文字列、
/// `sample_entry` は新しいエントリに切り替わったサンプルでのみ 4CC 文字列。
pub fn sample_json(index : Int32, sample : @mp4_demux.Sample) -> Json {
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
/// tracks / samples の配列 JSON を作る共有ヘルパー。
/// `samples` のうち先頭 `limit` 件を使う (`limit < 0` は全件)。
pub fn track_items_json(
  tracks : ArrayView[@mp4_demux.TrackInfo],
  codec_map~ : Map[UInt32, Json] = Map([]),
) -> Array[Json] {
  let items : Array[Json] = []
  for i, track in tracks {
    let codec = codec_map.get(track.track_id).unwrap_or(Json::null())
    items.push(track_json(i, track, codec~))
  }
  items
}

///|
/// 先頭 `limit` 件の Sample の JSON 配列を返す (`limit < 0` は全件)。
pub fn sample_items_json(
  samples : ArrayView[@mp4_demux.Sample],
  offset~ : Int32 = 0,
  limit~ : Int32 = -1,
) -> Array[Json] {
  let items : Array[Json] = []
  let end = if limit < 0 {
    samples.length()
  } else if offset + limit < samples.length() {
    offset + limit
  } else {
    samples.length()
  }
  for i in offset..<end {
    items.push(sample_json(i, samples[i]))
  }
  items
}

///|
/// 解析レポートの canonical JSON ドキュメント。
///
/// 共通フィールドの順序は `file`, `tracks`, `samples`, `shown_samples`,
/// `truncated` で固定する。`extra_fields` はこの直後に指定順で追加される
/// (Web デモが `box_tree` や `requests` を載せるための口)。
pub fn report_json(
  file~ : String,
  tracks : ArrayView[@mp4_demux.TrackInfo],
  samples : ArrayView[@mp4_demux.Sample],
  truncated~ : Bool,
  codec_map~ : Map[UInt32, Json] = Map([]),
  extra_fields~ : Array[(String, Json)] = [],
) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["file"] = Json(file)
  obj["tracks"] = Json(track_items_json(tracks, codec_map~))
  obj["samples"] = Json(sample_items_json(samples))
  obj["shown_samples"] = Json(samples.length())
  obj["truncated"] = Json(truncated)
  for field in extra_fields {
    obj[field.0] = field.1
  }
  Json::object(obj)
}

///|
/// canonical JSON ドキュメントの文字列表現 (2 スペースインデント + 末尾改行)。
pub fn report_json_string(doc : Json) -> String {
  doc.stringify(indent=2) + "\n"
}
