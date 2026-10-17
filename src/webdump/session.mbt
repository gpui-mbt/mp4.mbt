// ブラウザ MP4 dump デモ用の Sans I/O セッション。
//
// DOM / File API には一切触れず、`next_request` が要求する範囲を JS 側が
// `File.slice` で読んで `feed` に渡す。内部的には「先にトップレベルの
// ボックスヘッダーを走査 → kind 判定 → デマルチプレックス初期化 →
// moov 部分木の構築 → サンプル収集」の順に進め、実際に読まれた範囲は
// `read_log` に記録する (mdat ペイロードを読まないことの検証用)。
//
// キャンセルと世代管理は JS 側が `cancel` とセッション破棄で行う。

///|
/// セッションのフェーズ。
priv enum SessionPhase {
  /// トップレベルのボックスヘッダーを走査中 (次に読むべき位置)
  WalkHeaders(offset~ : UInt64)
  /// [`Mp4FileKindDetector`] を駆動中
  DetectKind
  /// [`Mp4FileDemuxer`] の初期化を駆動中
  InitDemux
  /// moov 部分木構築のために moov ボックス全体を読み込み中
  ReadMoov(offset~ : UInt64, size~ : UInt64)
  /// サンプル一覧を収集中
  CollectSamples
  /// 完了
  Ready
  /// JS 側からキャンセルされた
  Cancelled
  /// 回復不能なエラー
  Failed(kind~ : String, message~ : String, position~ : UInt64?)
}

///|
/// トップレベルボックス 1 件分の観測情報。
priv struct TopBox {
  type_name : String
  offset : UInt64
  /// ヘッダーが宣言したサイズ (size==0 のとき 0)
  declared_size : UInt64
  /// 実際の合計サイズ (size==0 はファイル末尾まで)
  total_size : UInt64
  header_size : UInt64
}

///|
/// ブラウザ MP4 dump セッション。
///
/// `file_size` は JS 側の `File.size`、その他のファイル内容は Sans I/O の
/// まま扱われる。`max_read` は 1 回の要求で読み込める最大サイズで、
/// これを超える要求が来た場合は `RequestTooLarge` エラーになる
/// (CLI の `--buffer-size` と同じ方針)。
pub struct WebDumpSession {
  file_name : String
  file_size : UInt64
  max_read : UInt64
  priv mut phase : SessionPhase
  priv kind_detector : @mp4_demux.Mp4FileKindDetector
  priv demuxer : @mp4_demux.Mp4FileDemuxer
  /// 現在 JS 側に投げている未解決の要求
  priv mut pending : @mp4_demux.RequiredInput?
  /// kind 判定の結果
  priv mut file_kind : @mp4_demux.Mp4FileKind?
  /// 走査済みトップレベルボックス
  priv top_boxes : Array[TopBox]
  /// moov ボックスの範囲 (走査で発見済みなら)
  priv mut moov_range : (UInt64, UInt64)?
  /// moov の子ボックス木 (moov ボックス読み込み後に構築)
  priv mut moov_children : Array[@boxes.BoxNode]
  /// 初期化済みのトラック一覧
  priv track_infos : Array[@mp4_demux.TrackInfo]
  /// 収集済みサンプル
  priv samples : Array[@mp4_demux.Sample]
  /// 実際に JS 側へ要求した読み込み範囲のログ
  priv read_log : Array[(UInt64, UInt64)]
  /// これまでに feed で受け取った範囲 (要求のキャッシュ用)
  priv fed_ranges : Array[(UInt64, Bytes)]
}

///|
/// セッションを生成する。
/// `max_read` は 1 回の読み込み要求の上限。0 は無制限を意味する。
pub fn WebDumpSession::new(
  file_name : String,
  file_size : UInt64,
  max_read : UInt64,
) -> WebDumpSession {
  {
    file_name,
    file_size,
    max_read,
    phase: WalkHeaders(offset=0UL),
    kind_detector: @mp4_demux.Mp4FileKindDetector::new(),
    demuxer: @mp4_demux.Mp4FileDemuxer::new(),
    pending: None,
    file_kind: None,
    top_boxes: [],
    moov_range: None,
    moov_children: [],
    track_infos: [],
    samples: [],
    read_log: [],
    fed_ranges: [],
  }
}

///|
/// 現在のフェーズ名 (進捗表示用)。
pub fn WebDumpSession::state(self : WebDumpSession) -> String {
  match self.phase {
    WalkHeaders(..) => "walk"
    DetectKind => "detect"
    InitDemux => "demux"
    ReadMoov(..) => "moov"
    CollectSamples => "collect"
    Ready => "ready"
    Cancelled => "cancelled"
    Failed(..) => "failed"
  }
}

///|
/// セッションをキャンセルする。`next_request` はこれ以降 `""` を返す。
pub fn WebDumpSession::cancel(self : WebDumpSession) -> Unit {
  match self.phase {
    Ready | Failed(..) => ()
    _ => {
      self.pending = None
      self.phase = Cancelled
    }
  }
}

///|
/// 要求の解決済みサイズを返す。`size=None` は「ファイル末尾まで」を
/// `file_size` に基づいて具体的な長さに解決する。
fn WebDumpSession::resolve_size(
  self : WebDumpSession,
  req : @mp4_demux.RequiredInput,
) -> UInt64 {
  match req.size {
    Some(size) => size
    None =>
      if req.position >= self.file_size {
        0UL
      } else {
        self.file_size - req.position
      }
  }
}

///|
/// 失敗状態に遷移させる。
fn WebDumpSession::fail(
  self : WebDumpSession,
  kind~ : String,
  message~ : String,
  position~ : UInt64? = None,
) -> Unit {
  self.pending = None
  self.phase = Failed(kind~, message~, position~)
}

///|
/// `DemuxError` を (kind, message, position) に分解する。
fn demux_error_fields(
  error : @mp4_demux.DemuxError,
) -> (String, String, UInt64?) {
  match error {
    DecodeError(inner) => {
      let @bytes.Mp4Error(kind~, reason~, offset~, ..) = inner
      (kind.to_string(), reason, offset)
    }
    SampleTableError(inner) => ("SampleTableError", inner.to_string(), None)
    InvalidState(message) => ("InvalidState", message, None)
    InputRequired(required) =>
      ("InputRequired", error.to_string(), Some(required.position))
  }
}

///|
/// `DemuxError` で失敗状態へ遷移する。
fn WebDumpSession::fail_demux(
  self : WebDumpSession,
  error : @mp4_demux.DemuxError,
) -> Unit {
  let (kind, message, position) = demux_error_fields(error)
  self.fail(kind~, message~, position~)
}

///|
/// キャッシュ済み feed 範囲から `req` を満たすスライスがあれば返す。
/// `size=None` の要求はファイル末尾までカバーしている範囲のみが使える。
fn WebDumpSession::serve_cached(
  self : WebDumpSession,
  req : @mp4_demux.RequiredInput,
) -> BytesView? {
  for entry in self.fed_ranges {
    let (position, data) = entry
    if position > req.position {
      continue
    }
    let rel = (req.position - position).to_int()
    let data_end = position + data.length().to_uint64()
    match req.size {
      Some(size) =>
        if req.position + size <= data_end {
          return Some(data[rel:])
        }
      None =>
        // ファイル末尾までのデータがキャッシュされている場合のみ使える
        if data_end >= self.file_size {
          return Some(data[rel:])
        }
    }
  }
  None
}

///|
/// 入力を現在のフェーズの処理系へ渡す。
fn WebDumpSession::deliver(
  self : WebDumpSession,
  input : @mp4_demux.Input,
) -> Unit {
  match self.phase {
    DetectKind => self.kind_detector.handle_input(input)
    InitDemux => self.demuxer.handle_input(input)
    WalkHeaders(offset~) => self.consume_box_header(input, offset)
    ReadMoov(offset~, size~) => self.consume_moov(input, offset, size)
    _ => ()
  }
}

///|
/// トップレベルボックスヘッダー 1 件を処理する。
fn WebDumpSession::consume_box_header(
  self : WebDumpSession,
  input : @mp4_demux.Input,
  offset : UInt64,
) -> Unit {
  if input.position > offset {
    self.fail(
      kind="InvalidInput",
      message="input does not cover the requested box header",
      position=Some(offset),
    )
    return
  }
  let rel = (offset - input.position).to_int()
  if rel >= input.data.length() {
    // EOF 相当: ヘッダーがそろわない
    self.fail(
      kind="InvalidData",
      message="truncated top-level box header at EOF",
      position=Some(offset),
    )
    return
  }
  let cursor = @bytes.ReadCursor::from_view(input.data[rel:], offset)
  let header : @box.BoxHeader = try @bytes.decode_from(cursor) catch {
    e => {
      self.fail_decode(e)
      return
    }
  } noraise {
    h => h
  }
  let declared = header.box_size().get()
  let header_size = header.external_size().to_uint64()
  if declared == 0UL {
    // size==0 のトップレベルボックスはファイル末尾まで
    let total = self.file_size - offset
    self.top_boxes.push({
      type_name: header.box_type().to_string(),
      offset,
      declared_size: declared,
      total_size: total,
      header_size,
    })
    if header.box_type().as_bytes() == b"moov" && self.moov_range is None {
      self.moov_range = Some((offset, total))
    }
    self.phase = DetectKind
    return
  }
  if declared > 0xFFFF_FFFF_FFFF_FFFFUL - offset {
    self.fail(
      kind="InvalidData",
      message="box offset overflow",
      position=Some(offset),
    )
    return
  }
  let total = declared
  self.top_boxes.push({
    type_name: header.box_type().to_string(),
    offset,
    declared_size: declared,
    total_size: total,
    header_size,
  })
  if header.box_type().as_bytes() == b"moov" && self.moov_range is None {
    self.moov_range = Some((offset, total))
  }
  let next = offset + total
  if next >= self.file_size {
    self.phase = DetectKind
  } else {
    self.phase = WalkHeaders(offset=next)
  }
}

///|
/// `Mp4Error` で失敗状態へ遷移する (JSON 側の kind は ErrorKind 名)。
fn WebDumpSession::fail_decode(
  self : WebDumpSession,
  error : @bytes.Mp4Error,
) -> Unit {
  let @bytes.Mp4Error(kind~, reason~, offset~, ..) = error
  self.fail(kind=kind.to_string(), message=reason, position=offset)
}

///|
/// moov ボックス全体のバイト列から部分木を構築する。
fn WebDumpSession::consume_moov(
  self : WebDumpSession,
  input : @mp4_demux.Input,
  offset : UInt64,
  size : UInt64,
) -> Unit {
  if input.position > offset ||
    input.position + input.data.length().to_uint64() < offset + size {
    self.fail(
      kind="InvalidInput",
      message="moov read did not cover the whole box",
      position=Some(offset),
    )
    return
  }
  let rel = (offset - input.position).to_int()
  let end = (offset + size - input.position).to_int()
  let cursor = @bytes.ReadCursor::from_view(input.data[rel:end], offset)
  let nodes = try @boxes.build_box_tree(cursor) catch {
    e => {
      self.fail_decode(e)
      return
    }
  } noraise {
    n => n
  }
  match nodes {
    [moov, ..] => self.moov_children = moov.children()
    _ => ()
  }
  self.phase = CollectSamples
}

///|
/// サンプルをすべて収集する。
fn WebDumpSession::collect_samples(self : WebDumpSession) -> Unit {
  while true {
    let next = try self.demuxer.next_sample() catch {
      e => {
        self.fail_demux(e)
        return
      }
    } noraise {
      s => s
    }
    match next {
      Some(sample) => self.samples.push(sample)
      None => break
    }
  }
  self.phase = Ready
}

///|
/// 次の要求を `pending` に設定する。要求がなければフェーズを進める。
/// `pending` が設定されなければ終端状態 (`ready` / `cancelled` / `failed`)。
fn WebDumpSession::pump(self : WebDumpSession) -> Unit {
  while true {
    match self.phase {
      Ready | Cancelled | Failed(..) => return
      CollectSamples => {
        self.collect_samples()
        continue
      }
      WalkHeaders(offset~) =>
        if offset >= self.file_size {
          self.phase = DetectKind
          continue
        } else {
          let remaining = self.file_size - offset
          let size = if remaining < 32UL { remaining } else { 32UL }
          let req = @mp4_demux.RequiredInput::{
            position: offset,
            size: Some(size),
          }
          if !self.try_advance_machine(req) {
            self.pending = Some(req)
            self.read_log.push((req.position, size))
            return
          }
        }
      ReadMoov(offset~, size~) => {
        let req = @mp4_demux.RequiredInput::{
          position: offset,
          size: Some(size),
        }
        if self.max_read > 0UL && size > self.max_read {
          self.fail(
            kind="RequestTooLarge",
            message="moov box size exceeds the per-read limit",
            position=Some(offset),
          )
          return
        }
        if !self.try_advance_machine(req) {
          self.pending = Some(req)
          self.read_log.push((req.position, size))
          return
        }
      }
      DetectKind =>
        match self.kind_detector.required_input() {
          Some(req) => if !self.try_machine_request(req) { return }
          None => {
            // 要求がないのに未判定 = エラーが内部に格納されている
            let kind_result = try self.kind_detector.file_kind() catch {
              e => {
                self.fail_demux(e)
                return
              }
            } noraise {
              k => k
            }
            match kind_result {
              Some(kind) => {
                self.file_kind = Some(kind)
                self.phase = InitDemux
                continue
              }
              None => {
                self.fail(
                  kind="InvalidState",
                  message="file kind detector stopped without a result",
                )
                return
              }
            }
          }
        }
      InitDemux =>
        match self.demuxer.required_input() {
          Some(req) => if !self.try_machine_request(req) { return }
          None => {
            let tracks_result = try self.demuxer.tracks() catch {
              e => {
                self.fail_demux(e)
                return
              }
            } noraise {
              t => t
            }
            for t in tracks_result {
              self.track_infos.push(t)
            }
            // moov 部分木の構築へ (キャッシュ命中なら内部で完結)
            match self.moov_range {
              Some((offset, size)) => {
                self.phase = ReadMoov(offset~, size~)
                continue
              }
              None => {
                self.phase = CollectSamples
                continue
              }
            }
          }
        }
    }
  }
}

///|
/// 次の要求を返す。なければ `None`。
pub fn WebDumpSession::next_request(
  self : WebDumpSession,
) -> @mp4_demux.RequiredInput? {
  match self.pending {
    Some(req) => return Some(req)
    None => ()
  }
  match self.phase {
    Ready | Cancelled | Failed(..) => return None
    _ => ()
  }
  self.pump()
  self.pending
}

///|
/// DetectKind / InitDemux 用の要求を処理する。内部で充足可能なら true を返す。
fn WebDumpSession::try_machine_request(
  self : WebDumpSession,
  req : @mp4_demux.RequiredInput,
) -> Bool {
  // ファイル末尾を越える要求には空入力を届けて上流の EOF エラーを発生させる
  if req.position >= self.file_size {
    self.deliver(@mp4_demux.Input::{ position: req.position, data: [], })
    return true
  }
  let resolved = self.resolve_size(req)
  if self.max_read > 0UL && resolved > self.max_read {
    self.fail(
      kind="RequestTooLarge",
      message="required input exceeds the per-read limit",
      position=Some(req.position),
    )
    return true
  }
  match self.serve_cached(req) {
    Some(view) => {
      self.deliver(@mp4_demux.Input::{ position: req.position, data: view, })
      true
    }
    None => {
      self.pending = Some(req)
      self.read_log.push((req.position, resolved))
      false
    }
  }
}

///|
/// `req` がキャッシュで充足できるなら内部 feed して true を返す。
fn WebDumpSession::try_advance_machine(
  self : WebDumpSession,
  req : @mp4_demux.RequiredInput,
) -> Bool {
  match self.serve_cached(req) {
    Some(view) => {
      self.deliver(@mp4_demux.Input::{ position: req.position, data: view, })
      true
    }
    None => false
  }
}

///|
/// 要求 JSON を作る。
fn request_json(position : UInt64, size : UInt64?) -> String {
  let obj : Map[String, Json] = Map([])
  obj["position"] = Json(position.to_string())
  obj["size"] = match size {
    Some(s) => Json(s.to_string())
    None => Json::null()
  }
  Json::object(obj).stringify()
}

///|
/// JS 側からの feed。`data` は `next_request` が返した範囲のバイト列。
///
/// 厳密な範囲一致は要求しない: 短い入力は各処理系のデコードエラーとして
/// 報告される (上流の `handle_input` と同じ方針)。
fn WebDumpSession::feed(self : WebDumpSession, data : Bytes) -> Unit {
  match self.pending {
    None => ()
    Some(req) => {
      self.pending = None
      self.fed_ranges.push((req.position, data))
      self.deliver(@mp4_demux.Input::{ position: req.position, data: data[:], })
    }
  }
}

///|
/// BoxNode 1 ノードの JSON 表現 (再帰)。
fn box_node_json(node : @boxes.BoxNode) -> Json {
  let children : Array[Json] = []
  for child in node.children() {
    children.push(box_node_json(child))
  }
  let obj : Map[String, Json] = Map([])
  obj["type"] = Json(node.box_type().to_string())
  obj["offset"] = Json(node.start().to_string())
  obj["size"] = Json(node.total_size().to_string())
  obj["declared_size"] = Json(node.declared_size().to_string())
  obj["header_size"] = Json(node.header_bytes())
  obj["children"] = Json(children)
  Json::object(obj)
}

///|
/// トップレベルボックスの JSON 表現。moov には構築済みの子木を載せる。
fn WebDumpSession::top_box_json(self : WebDumpSession, top : TopBox) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["type"] = Json(top.type_name)
  obj["offset"] = Json(top.offset.to_string())
  obj["size"] = Json(top.total_size.to_string())
  obj["declared_size"] = Json(top.declared_size.to_string())
  obj["header_size"] = Json(top.header_size)
  let children : Array[Json] = []
  if top.type_name == "moov" {
    for child in self.moov_children {
      children.push(box_node_json(child))
    }
  }
  obj["children"] = Json(children)
  Json::object(obj)
}

///|
/// Box Tree 全体の JSON (`[node, ...]`)。
pub fn WebDumpSession::box_tree_json(self : WebDumpSession) -> Json {
  let items : Array[Json] = []
  for top in self.top_boxes {
    items.push(self.top_box_json(top))
  }
  Json(items)
}

///|
/// 失敗時のエラー情報 JSON。未失敗なら `null`。
fn WebDumpSession::error_json_value(self : WebDumpSession) -> Json {
  match self.phase {
    Failed(kind~, message~, position~) => {
      let obj : Map[String, Json] = Map([])
      obj["kind"] = Json(kind)
      obj["message"] = Json(message)
      obj["position"] = match position {
        Some(p) => Json(p.to_string())
        None => Json::null()
      }
      Json::object(obj)
    }
    _ => Json::null()
  }
}

///|
/// エラー情報の JSON 文字列 (失敗していなければ空文字列)。
pub fn WebDumpSession::error_json(self : WebDumpSession) -> String {
  match self.phase {
    Failed(..) => self.error_json_value().stringify()
    _ => ""
  }
}

///|
/// kind 判定結果の表示名。
fn file_kind_name(kind : @mp4_demux.Mp4FileKind) -> String {
  match kind {
    Mp4 => "normal"
    FragmentedMp4 => "fragmented"
  }
}

///|
/// 読み込み要求ログの JSON。
pub fn WebDumpSession::read_log_json(self : WebDumpSession) -> Json {
  let items : Array[Json] = []
  let mut total = 0UL
  for entry in self.read_log {
    let (position, size) = entry
    let obj : Map[String, Json] = Map([])
    obj["position"] = Json(position.to_string())
    obj["size"] = Json(size.to_string())
    items.push(Json::object(obj))
    total = total + size
  }
  let obj : Map[String, Json] = Map([])
  obj["requests"] = Json(items)
  obj["total_bytes"] = Json(total.to_string())
  obj["file_size"] = Json(self.file_size.to_string())
  Json::object(obj)
}

///|
/// トラック一覧の JSON。codec は収集済みサンプルから推定する。
pub fn WebDumpSession::tracks_json(self : WebDumpSession) -> Json {
  let codec_map = @demux_report.track_codec_map(self.samples[:])
  Json(@demux_report.track_items_json(self.track_infos[:], codec_map~))
}

///|
/// エンコードに失敗した場合は `None` を返す。
fn webdump_encode_bytes(f : () -> Bytes raise @bytes.Mp4Error) -> Bytes? {
  try f() catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
/// 各トラックの codec 設定 bytes を base64 で返す。
///
/// WebCodecs の `VideoDecoderConfig.description` 用。`avc1` は `avcC`、
/// `hev1`/`hvc1` は `hvcC`、`av01` は `av1C` のペイロード（ボックスヘッダーを除く）
/// を返す。設定が取れないトラックは `description_b64` が `null` になる。
pub fn WebDumpSession::codec_config_json(self : WebDumpSession) -> Json {
  let items : Array[Json] = []
  for track in self.track_infos {
    let mut entry : @boxes.SampleEntry? = None
    let mut found = false
    for sample in self.samples {
      if !found && sample.track.track_id == track.track_id {
        match sample.sample_entry {
          Some(value) => {
            entry = Some(value)
            found = true
          }
          None => ()
        }
      }
    }
    let mut entry_type : Json = Json::null()
    let mut description : Json = Json::null()
    let mut width : Json = Json(0)
    let mut height : Json = Json(0)
    match entry {
      Some(value) => {
        entry_type = Json(value.box_type().to_string())
        match value.video_resolution() {
          Some((w, h)) => {
            width = Json(w)
            height = Json(h)
          }
          None => ()
        }
        let raw : Bytes? = match value {
          @boxes.SampleEntry::Avc1(b) =>
            webdump_encode_bytes(fn() raise @bytes.Mp4Error {
              @bytes.encode_to_bytes(b.avcc_box)
            })
          @boxes.SampleEntry::Hev1(b) =>
            webdump_encode_bytes(fn() raise @bytes.Mp4Error {
              @bytes.encode_to_bytes(b.hvcc_box)
            })
          @boxes.SampleEntry::Hvc1(b) =>
            webdump_encode_bytes(fn() raise @bytes.Mp4Error {
              @bytes.encode_to_bytes(b.hvcc_box)
            })
          @boxes.SampleEntry::Av01(b) => Some(b.av1c_box.config_obus)
          @boxes.SampleEntry::Vp09(b) =>
            webdump_encode_bytes(fn() raise @bytes.Mp4Error {
              @bytes.encode_to_bytes(b.vpcc_box)
            })
          _ => None
        }
        description = match raw {
          Some(bytes) => {
            let payload = if bytes.length() > 8 {
              bytes[8:].to_owned()
            } else {
              bytes
            }
            Json(@base64.encode(payload[:]))
          }
          None => Json::null()
        }
      }
      None => ()
    }
    items.push({
      "track_id": track.track_id,
      "sample_entry": entry_type,
      "width": width,
      "height": height,
      "description_b64": description,
    })
  }
  Json(items)
}

///|
/// サンプル一覧の窓 JSON。`offset` から最大 `count` 件 (上限 10000)。
pub fn WebDumpSession::samples_json(
  self : WebDumpSession,
  offset~ : Int32,
  count~ : Int32,
) -> Json {
  let clamped_count = if count < 0 || count > 10000 { 10000 } else { count }
  let items = @demux_report.sample_items_json(
    self.samples[:],
    offset~,
    limit=clamped_count,
  )
  let obj : Map[String, Json] = Map([])
  obj["offset"] = Json(offset)
  obj["count"] = Json(items.length())
  obj["total"] = Json(self.samples.length())
  obj["samples"] = Json(items)
  Json::object(obj)
}

///|
/// 解析レポート全体の canonical JSON。
/// `max_samples` は `samples` に含める最大件数 (0 以下は全件)。
/// 共通フィールドの順序と 64bit の十進文字列表現は CLI と同一。
pub fn WebDumpSession::report_json(
  self : WebDumpSession,
  max_samples~ : Int32,
) -> Json {
  let shown = if max_samples <= 0 || max_samples > self.samples.length() {
    self.samples.length()
  } else {
    max_samples
  }
  let codec_map = @demux_report.track_codec_map(self.samples[:])
  let shown_samples = self.samples[:shown]
  let format : Json = match self.file_kind {
    Some(kind) => Json(file_kind_name(kind))
    None => Json::null()
  }
  let extra : Array[(String, Json)] = [
    ("file_size", Json(self.file_size.to_string())),
    ("format", format),
    ("state", Json(self.state())),
    ("sample_total", Json(self.samples.length())),
    ("box_tree", self.box_tree_json()),
    ("requests", self.read_log_json()),
    ("error", self.error_json_value()),
  ]
  @demux_report.report_json(
    file=self.file_name,
    self.track_infos[:],
    shown_samples,
    truncated=shown < self.samples.length(),
    codec_map~,
    extra_fields=extra,
  )
}

// ===== JS エクスポート境界 =====

///|
/// 新しいセッションを作る。JS からは `mp4dump_create` として見える。
#export_name("mp4dump_create")
pub fn mp4dump_create(
  file_name : String,
  file_size : UInt64,
  max_read : UInt64,
) -> WebDumpSession {
  WebDumpSession::new(file_name, file_size, max_read)
}

///|
/// 次の読み込み要求を返す。要求がなければ `""`。
/// 戻り値の JSON は `{"position":"10進","size":"10進"}`。
#export_name("mp4dump_next_request")
pub fn mp4dump_next_request(session : WebDumpSession) -> String {
  match session.next_request() {
    Some(req) => request_json(req.position, Some(session.resolve_size(req)))
    None => ""
  }
}

///|
/// `next_request` が返した範囲のバイト列を投入する。
#export_name("mp4dump_feed")
pub fn mp4dump_feed(session : WebDumpSession, data : Bytes) -> Unit {
  session.feed(data)
}

///|
/// 現在の状態名を返す。
#export_name("mp4dump_state")
pub fn mp4dump_state(session : WebDumpSession) -> String {
  session.state()
}

///|
/// セッションをキャンセルする。
#export_name("mp4dump_cancel")
pub fn mp4dump_cancel(session : WebDumpSession) -> Unit {
  session.cancel()
}

///|
/// canonical JSON レポートを返す。`max_samples <= 0` で全サンプル。
#export_name("mp4dump_report_json")
pub fn mp4dump_report_json(
  session : WebDumpSession,
  max_samples : Int32,
) -> String {
  @demux_report.report_json_string(session.report_json(max_samples~))
}

///|
/// サンプル一覧の窓を返す (遅延描画用)。
#export_name("mp4dump_samples_json")
pub fn mp4dump_samples_json(
  session : WebDumpSession,
  offset : Int32,
  count : Int32,
) -> String {
  session.samples_json(offset~, count~).stringify()
}

///|
/// トラック一覧を返す。
#export_name("mp4dump_codec_config_json")
pub fn mp4dump_codec_config_json(session : WebDumpSession) -> String {
  @demux_report.report_json_string(session.codec_config_json())
}

///|
#export_name("mp4dump_tracks_json")
pub fn mp4dump_tracks_json(session : WebDumpSession) -> String {
  session.tracks_json().stringify()
}

///|
/// Box Tree を返す。
#export_name("mp4dump_box_tree_json")
pub fn mp4dump_box_tree_json(session : WebDumpSession) -> String {
  session.box_tree_json().stringify()
}

///|
/// 読み込み要求ログを返す。
#export_name("mp4dump_read_log_json")
pub fn mp4dump_read_log_json(session : WebDumpSession) -> String {
  session.read_log_json().stringify()
}

///|
/// エラー情報を返す (失敗していなければ `""`)。
#export_name("mp4dump_error_json")
pub fn mp4dump_error_json(session : WebDumpSession) -> String {
  session.error_json()
}

///|
/// 差分 Lab: oracle (Rust/WASM) と candidate (MoonBit/JS) の観測 JSON を
/// 突き合わせ、field path 単位の差分レポート JSON を返す (issue 0016)。
/// 入力はいずれも JSON 文字列。parse 失敗は JSON エラーレポートとして返す。
#export_name("mp4lab_compare_json")
pub fn mp4lab_compare_json(
  oracle_json : String,
  candidate_json : String,
  meta_json : String,
) -> String {
  try @difflab.diff_reports_json(oracle_json, candidate_json, meta_json) catch {
    _ =>
      // parse 失敗は UNVERIFIED (FAIL と混同しない)
      @difflab.unverified_report(
        @json.parse(meta_json[:]) catch {
          _ => Json::null()
        },
        "invalid input JSON to comparator",
      ).stringify()
  } noraise {
    v => v
  }
}

///|
/// 差分 Lab: 実行不能 (oracle wasm 不在 / candidate ビルド失敗) の
/// UNVERIFIED レポートを生成する。
#export_name("mp4lab_unverified_json")
pub fn mp4lab_unverified_json(meta_json : String, reason : String) -> String {
  let meta = @json.parse(meta_json[:]) catch { _ => Json::null() }
  @difflab.unverified_report(meta, reason).stringify()
}
