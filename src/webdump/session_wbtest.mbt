// WebDumpSession の振る舞いテスト (白箱)。
// JS 側の `File.slice` + `arrayBuffer` に相当するスライス応答を `serve` で模倣する。

///|
/// JS アダプタ相当の駆動ループ: `next_request` の範囲を `data` から切り出して
/// `feed` する。戻り値は実際に行った feed の範囲列。
fn drive(session : WebDumpSession, data : Bytes) -> Array[(UInt64, UInt64)] {
  let fed : Array[(UInt64, UInt64)] = []
  let mut steps = 0
  while true {
    guard steps < 10000 else { abort("session did not terminate") }
    steps += 1
    match session.next_request() {
      None => break
      Some(req) => {
        let position = req.position
        let size = session.resolve_size(req)
        let start = position.to_int()
        let end = start + size.to_int()
        let avail_end = if end > data.length() { data.length() } else { end }
        let slice = data[start:avail_end]
        session.feed(slice.to_owned())
        fed.push((position, size))
      }
    }
  }
  fed
}

///|
test "正常系: 全フェーズを完了し ready になる (mdat ペイロードは要求しない)" {
  let s = WebDumpSession::new(
    "black-h264-video.mp4",
    fixture_black_h264.length().to_uint64(),
    64UL * 1024UL * 1024UL,
  )
  let fed = drive(s, fixture_black_h264)
  assert_eq(s.state(), "ready")
  assert_eq(s.error_json(), "")
  // 要求列: トップレベルヘッダー 4 件 + moov 本体。mdat (804B) の
  // ペイロードは要求されない
  assert_eq(fed, [
    (0UL, 32UL),
    (32UL, 32UL),
    (40UL, 32UL),
    (844UL, 32UL),
    (844UL, 791UL),
  ])
  // トラック + codec
  let tracks = s.tracks_json().stringify()
  assert_true(tracks.contains("\"codec\":\"avc1.64001e\""))
  assert_true(tracks.contains("\"kind\":\"video\""))
  // Box Tree: moov の子に trak がいる
  let tree = s.box_tree_json().stringify()
  assert_true(tree.contains("\"type\":\"moov\""))
  assert_true(tree.contains("\"type\":\"trak\""))
  assert_true(tree.contains("\"type\":\"stbl\""))
  // サンプル 1 件
  let samples = s.samples_json(offset=0, count=10).stringify()
  assert_true(samples.contains("\"total\":1"))
  assert_true(samples.contains("\"data_offset\":\"48\""))
}

///|
test "canonical JSON: 64bit は十進文字列、共通フィールドの順序が固定" {
  let s = WebDumpSession::new(
    "black-h264-video.mp4",
    fixture_black_h264.length().to_uint64(),
    64UL * 1024UL * 1024UL,
  )
  let _ = drive(s, fixture_black_h264)
  let doc = @demux_report.report_json_string(s.report_json(max_samples=0))
  // 共通フィールドが先頭に固定順で並ぶ
  let head_order = "\"file\": \"black-h264-video.mp4\""
  assert_true(doc.contains(head_order))
  let file_pos = doc.find("\"file\":").unwrap()
  let tracks_pos = doc.find("\"tracks\":").unwrap()
  let samples_pos = doc.find("\"samples\":").unwrap()
  let shown_pos = doc.find("\"shown_samples\":").unwrap()
  let truncated_pos = doc.find("\"truncated\":").unwrap()
  assert_true(file_pos < tracks_pos)
  assert_true(tracks_pos < samples_pos)
  assert_true(samples_pos < shown_pos)
  assert_true(shown_pos < truncated_pos)
  // 64bit 値は十進文字列
  assert_true(doc.contains("\"file_size\": \"1635\""))
  assert_true(doc.contains("\"duration\": \"512\""))
  assert_true(doc.contains("\"data_offset\": \"48\""))
  // 64bit 値は数値ではなく文字列として出る ("1635" にクォートが付く)
  assert_true(!doc.contains("\"file_size\": 1635,"))
}

///|
test "sample_total と max_samples の打ち切り" {
  let s = WebDumpSession::new(
    "black-h264-video.mp4",
    fixture_black_h264.length().to_uint64(),
    1024UL * 1024UL,
  )
  let _ = drive(s, fixture_black_h264)
  // fixture はサンプル 1 件のみ
  let doc = @demux_report.report_json_string(s.report_json(max_samples=1))
  assert_true(doc.contains("\"sample_total\": 1"))
  assert_true(doc.contains("\"truncated\": false"))
}

///|
test "切り詰められたファイルは InvalidData で失敗する (パニックしない)" {
  let truncated = fixture_black_h264[:100].to_owned()
  let s = WebDumpSession::new(
    "truncated.mp4",
    truncated.length().to_uint64(),
    64UL * 1024UL * 1024UL,
  )
  let _ = drive(s, truncated)
  assert_eq(s.state(), "failed")
  let err = s.error_json()
  assert_true(err.contains("InvalidData"))
  assert_true(err.contains("moov box not found"))
}

///|
test "非 MP4 データはパニックせず失敗を返す" {
  let garbage : Bytes = b"not an mp4 file at all"
  let s = WebDumpSession::new(
    "garbage.bin",
    garbage.length().to_uint64(),
    64UL * 1024UL * 1024UL,
  )
  let _ = drive(s, garbage)
  assert_eq(s.state(), "failed")
  assert_true(s.error_json().contains("\"kind\""))
}

///|
test "cancel: 以降の next_request は空で状態は cancelled" {
  let s = WebDumpSession::new(
    "x.mp4",
    fixture_black_h264.length().to_uint64(),
    1024UL * 1024UL,
  )
  ignore(s.next_request())
  s.cancel()
  assert_eq(s.state(), "cancelled")
  assert_true(s.next_request() is None)
}

///|
test "世代: 2 セッションは独立 (古いセッションの結果が新しいものを汚染しない)" {
  let a = WebDumpSession::new(
    "a.mp4",
    fixture_black_h264.length().to_uint64(),
    0UL,
  )
  let b = WebDumpSession::new(
    "b.mp4",
    fixture_black_h264.length().to_uint64(),
    64UL * 1024UL,
  )
  // a を途中で止めて b を最後まで流す
  ignore(a.next_request())
  let _ = drive(b, fixture_black_h264)
  assert_eq(b.state(), "ready")
  assert_eq(a.state(), "walk")
  // b の結果が a に漏れない
  assert_true(a.tracks_json().stringify() == "[]")
}

///|
test "max_read 超過は RequestTooLarge" {
  let s = WebDumpSession::new(
    "big-moov.mp4",
    fixture_black_h264.length().to_uint64(),
    512UL, // moov (791B) が上限超過
  )
  let _ = drive(s, fixture_black_h264)
  assert_eq(s.state(), "failed")
  assert_true(s.error_json().contains("RequestTooLarge"))
}

///|
test "samples_json の窓指定" {
  let s = WebDumpSession::new(
    "black-h264-video.mp4",
    fixture_black_h264.length().to_uint64(),
    64UL * 1024UL * 1024UL,
  )
  let _ = drive(s, fixture_black_h264)
  let w = s.samples_json(offset=1, count=10).stringify()
  assert_true(w.contains("\"count\":0"))
  assert_true(w.contains("\"total\":1"))
  let w0 = s.samples_json(offset=0, count=1).stringify()
  assert_true(w0.contains("\"count\":1"))
}
