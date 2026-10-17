// gpui.mbt Native MP4 Inspector。
// moov / track / sample metadata だけを range read し、全ファイルを読み込まない。

///|
fn inspector_rect(x : Double, y : Double, w : Double, h : Double) -> @primitives.Rect {
  match @primitives.Rect::new(x, y, w, h) {
    Ok(r) => r
    Err(_) => abort("invalid rect")
  }
}

///|
fn inspector_color(r : Int, g : Int, b : Int) -> @primitives.Color {
  match @primitives.Color::rgba(r, g, b, 255) {
    Ok(c) => c
    Err(_) => abort("invalid color")
  }
}

///|
fn text_item(
  id : UInt64,
  x : Double,
  y : Double,
  text : String,
) -> @scene.SceneItem {
  match @scene.SceneItem::text(
    id,
    inspector_rect(x, y, 980.0, 18.0),
    text,
    13.0,
    inspector_color(235, 235, 235),
    @scene.AffineTransform::identity(),
    1.0,
    None,
  ) {
    Ok(item) => item
    Err(_) => abort("invalid text item")
  }
}

///|
fn inspector_scene(
  width : Double,
  height : Double,
  scale : Double,
  lines : Array[String],
) -> @scene.SceneSnapshot {
  let items : Array[@scene.SceneItem] = [
    match @scene.SceneItem::quad(
      1,
      inspector_rect(0.0, 0.0, width, height),
      inspector_color(24, 26, 30),
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ) {
      Ok(item) => item
      Err(_) => abort("invalid quad item")
    },
  ]
  let mut i = 0
  while i < lines.length() {
    let y = 16.0 + i.to_double() * 18.0
    if y + 18.0 > height {
      break
    }
    items.push(text_item((i + 2).to_uint64(), 16.0, y, lines[i]))
    i = i + 1
  }
  match @scene.SceneSnapshot::new(
    inspector_rect(0.0, 0.0, width, height),
    scale,
    [],
    [],
    items,
  ) {
    Ok(snapshot) => snapshot
    Err(_) => abort("invalid scene snapshot")
  }
}

///|
/// range read の回数と総バイト数。
struct ReadStats {
  mut reads : Int
  mut bytes : UInt64
}

///|
/// 1 回のファイル読み取りを記録する。
async fn read_at(
  file : @fs.File,
  stats : ReadStats,
  position : Int64,
  size : Int,
) -> Bytes {
  if size <= 0 {
    return b""
  }
  let bytes = file.read_exactly_at(size, position=position) catch {
    _ => b""
  }
  stats.reads = stats.reads + 1
  stats.bytes = stats.bytes + bytes.length().to_uint64()
  bytes
}

///|
/// ファイル先頭から top-level box を走査し、moov の部分木だけを読む。
async fn box_rows_from_file(
  file : @fs.File,
  file_size : Int64,
  stats : ReadStats,
) -> Array[String] {
  let rows : Array[String] = []
  let mut offset : Int64 = 0
  while offset + 8L <= file_size {
    let header_bytes = read_at(file, stats, offset, 32)
    if header_bytes.length() < 8 {
      break
    }
    let header : @box.BoxHeader = @bytes.decode_from(
      @bytes.ReadCursor::from_view(header_bytes[:], offset.reinterpret_as_uint64()),
    ) catch {
      _ => break
    }
    let declared = header.box_size().get()
    let box_size : Int64 = if declared == 0UL {
      file_size - offset
    } else {
      declared.reinterpret_as_int64()
    }
    if box_size < 8L || offset + box_size > file_size {
      break
    }
    if header.box_type().as_bytes() == b"moov" {
      let moov_bytes = read_at(file, stats, offset, box_size.to_int())
      if moov_bytes.length().to_int64() == box_size {
        let cursor = @bytes.ReadCursor::from_view(
          moov_bytes[:],
          offset.reinterpret_as_uint64(),
        )
        let tree = @boxes.build_box_tree(cursor) catch {
          _ => []
        }
        for row in @inspect.box_rows(tree) {
          rows.push(row)
        }
      }
      break
    }
    offset = offset + box_size
  }
  rows
}

///|
/// Sans I/O demuxer に range read で入力を供給する。
async fn feed_demuxer(
  file : @fs.File,
  file_size : Int64,
  demuxer : @mp4_demux.Mp4FileDemuxer,
  stats : ReadStats,
) -> Unit {
  while demuxer.required_input() is Some(required) {
    let position = required.position.reinterpret_as_int64()
    let remaining = if file_size > position { file_size - position } else { 0L }
    let size : Int64 = match required.size {
      Some(size) => {
        let wanted = size.reinterpret_as_int64()
        if wanted > remaining { remaining } else { wanted }
      }
      None => if remaining > 1048576L { 1048576L } else { remaining }
    }
    let data = read_at(file, stats, position, size.to_int())
    demuxer.handle_input(
      @mp4_demux.Input::{ position: required.position, data: data[:] },
    )
  }
}

///|
async fn build_lines(
  path : String,
  status_path : String?,
) -> Array[String] {
  let lines : Array[String] = ["file: " + path]
  let file = @fs.open(path, mode=ReadOnly) catch {
    _ => {
      lines.push("cannot open file")
      return lines
    }
  }
  defer file.close()
  let file_size = file.size() catch {
    _ => {
      lines.push("cannot stat file")
      return lines
    }
  }
  let stats : ReadStats = { reads: 0, bytes: 0UL }
  lines.push("size: \{file_size} bytes")
  for row in box_rows_from_file(file, file_size, stats) {
    lines.push(row)
  }
  let demuxer = @mp4_demux.Mp4FileDemuxer::new()
  feed_demuxer(file, file_size, demuxer, stats)
  let tracks = demuxer.tracks() catch {
    _ => []
  }
  for row in @inspect.track_rows(tracks) {
    lines.push(row)
  }
  let samples : Array[@mp4_demux.Sample] = []
  while samples.length() < 100000 {
    let next = demuxer.next_sample() catch {
      @mp4_demux.InputRequired(_) => None
      _ => None
    } noraise {
      v => v
    }
    match next {
      Some(sample) => samples.push(sample)
      None => break
    }
  }
  // 仮想リスト: 画面には先頭 40 件だけを描画する。
  for row in @inspect.sample_rows(samples, 0, 40) {
    lines.push(row)
  }
  if samples.length() > 0 {
    let sample = samples[0]
    let hex_size = if sample.data_size > 256U {
      256
    } else {
      sample.data_size.reinterpret_as_int()
    }
    let payload = read_at(
      file,
      stats,
      sample.data_offset.reinterpret_as_int64(),
      hex_size,
    )
    for row in @inspect.hex_dump(payload, 16) {
      lines.push("hex: " + row)
    }
  }
  lines.push(
    "samples: \{samples.length()} (rendered 40), reads: \{stats.reads}, read_bytes: \{stats.bytes}, file_bytes: \{file_size}",
  )
  match status_path {
    Some(path) =>
      @fs.write_file(
        path,
        "ok rows=\{lines.length()} samples=\{samples.length()} reads=\{stats.reads} bytes=\{stats.bytes} file=\{file_size}",
      )
    None => ()
  }
  lines
}

///|
async fn write_status(path : String?, text : String) -> Unit {
  match path {
    Some(path) => @fs.write_file(path, text)
    None => ()
  }
}

///|
async fn run(smoke : Bool, path : String, status_path : String?) -> Unit {
  let lines = build_lines(path, status_path)
  let host = match @macos.Host::start() {
    Ok(host) => host
    Err(e) => {
      write_status(
        status_path,
        "error: macOS host start failed " + e.operation() + ":" + e.code().label(),
      )
      return
    }
  }
  let window = match host.create_window(
    "mp4.mbt Inspector — " + path,
    1000.0,
    700.0,
  ) {
    Ok(window) => window
    Err(e) => {
      write_status(
        status_path,
        "error: window creation failed " + e.operation() + ":" + e.code().label(),
      )
      return
    }
  }
  let (window_width, window_height, scale) = match host.window_metrics(window) {
    Ok(metrics) => metrics
    Err(e) => {
      write_status(
        status_path,
        "error: window_metrics failed " + e.operation() + ":" + e.code().label(),
      )
      return
    }
  }
  let snapshot = inspector_scene(window_width, window_height, scale, lines)
  match host.present(window, snapshot) {
    Ok(_) => ()
    Err(e) => {
      write_status(
        status_path,
        "error: present failed " + e.operation() + ":" + e.code().label(),
      )
      return
    }
  }
  if smoke {
    match host.destroy_window(window) {
      Ok(_) => ()
      Err(_) => ()
    }
    match host.stop() {
      Ok(_) => ()
      Err(_) => ()
    }
    println("inspector smoke: rows=\{lines.length()}")
    return
  }
  let mut done = false
  while !done {
    let event = match host.next_event() {
      Ok(event) => event
      Err(_) => break
    }
    match event {
      None => ()
      Some(e) => {
        if e.kind is @platform.CloseRequested ||
          e.kind is @platform.Destroyed {
          done = true
        }
        if e.kind is @platform.Input(@primitives.KeyPressed(key=@primitives.Escape, ..)) {
          done = true
        }
      }
    }
  }
  match host.destroy_window(window) {
    Ok(_) => ()
    Err(_) => ()
  }
  match host.stop() {
    Ok(_) => ()
    Err(_) => ()
  }
}

///|
async fn pick_file() -> String {
  let output = @shell.Cmd(
    "osascript",
    [
      "-e",
      "POSIX path of (choose file with prompt \"Select an MP4\" of type {\"public.mpeg-4\"})",
    ],
  ).output() catch {
    _ => return ""
  }
  if output.exit_code() != 0 {
    return ""
  }
  output.stdout().trim().to_owned()
}

///|
async fn main {
  let args = @env.args()
  let smoke = args.contains("--smoke")
  let pick = args.contains("--pick")
  let mut path = ""
  let mut status_path : String? = None
  let mut i = 1
  while i < args.length() {
    if args[i] == "--status" && i + 1 < args.length() {
      status_path = Some(args[i + 1])
      i = i + 1
    } else if args[i] != "--smoke" && args[i] != "--pick" {
      path = args[i]
    }
    i = i + 1
  }
  if path == "" && pick {
    path = pick_file()
  }
  if path == "" {
    println("usage: inspector <file.mp4> [--pick] [--smoke] [--status PATH]")
    return
  }
  run(smoke, path, status_path) catch {
    _ => ()
  }
}
