// Native Inspector / Web Dump が共有する portable な表示モデル。
// gpui / OS / DOM には依存しない。

///|
/// box tree を表示用の行にする。
pub fn box_rows(nodes : Array[@boxes.BoxNode]) -> Array[String] {
  let rows : Array[String] = []
  for entry in @boxes.flatten_box_tree(nodes) {
    let (depth, node) = entry
    rows.push(node.dump_line(depth))
  }
  rows
}

///|
/// トラック一覧を表示用の行にする。
pub fn track_rows(tracks : Array[@demux.TrackInfo]) -> Array[String] {
  let rows : Array[String] = []
  for track in tracks {
    rows.push(
      "track_id=\{track.track_id} kind=\{@demux_report.track_kind_name(track.kind)} timescale=\{track.timescale.get()} duration=\{track.duration}",
    )
  }
  rows
}

///|
/// sample の仮想ウィンドウを表示用の行にする。
///
/// `offset` と `count` で必要な範囲だけを返す。UI はこの範囲だけを描画する。
pub fn sample_rows(
  samples : Array[@demux.Sample],
  offset : Int32,
  count : Int32,
) -> Array[String] {
  let rows : Array[String] = []
  let start = if offset < 0 { 0 } else { offset }
  let end = if start + count > samples.length() {
    samples.length()
  } else {
    start + count
  }
  let mut i = start
  while i < end {
    let sample = samples[i]
    let cto = match sample.composition_time_offset {
      Some(value) => value.to_string()
      None => "none"
    }
    rows.push(
      "index=\{i} track_id=\{sample.track.track_id} keyframe=\{sample.keyframe} dts=\{sample.timestamp} duration=\{sample.duration} cto=\{cto} offset=\{sample.data_offset} size=\{sample.data_size}",
    )
    i = i + 1
  }
  rows
}

///|
/// 選択サンプルの hex dump を返す。
pub fn hex_dump(data : Bytes, width : Int32) -> Array[String] {
  let rows : Array[String] = []
  let row_width = if width <= 0 { 16 } else { width }
  let digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let mut i = 0
  while i < data.length() {
    let builder = StringBuilder()
    let mut j = 0
    while j < row_width && i + j < data.length() {
      let value = data[i + j].to_uint().reinterpret_as_int()
      builder.write_char(digits[(value >> 4) & 0xF])
      builder.write_char(digits[value & 0xF])
      builder.write_char(' ')
      j = j + 1
    }
    rows.push("\{i}: \{builder.to_string()}")
    i = i + row_width
  }
  rows
}
