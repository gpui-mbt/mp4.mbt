///|
/// `oracle_kind_detector_cases` から名前で 1 件取り出す。
fn kind_case(name : String) -> OracleKindDetectorCase {
  for case in oracle_kind_detector_cases {
    if case.name == name {
      return case
    }
  }
  abort("missing oracle case: \{name}")
}

///|
/// `required_input()` の要求に応じて `data[position..]` を供給する
/// 上流ドキュメント例と同じドライバー。
fn feed_until_done(detector : @demux.Mp4FileKindDetector, data : Bytes) -> Unit {
  for required = detector.required_input() {
    match required {
      Some(required) => {
        let start = if required.position <= data.length().to_uint64() {
          required.position.to_int()
        } else {
          data.length()
        }
        detector.handle_input(@demux.Input::{
          position: required.position,
          data: data[start:],
        })
        continue detector.required_input()
      }
      None => break
    }
  }
}

///|
test "initial required input is the max box-header range" {
  let detector = @demux.Mp4FileKindDetector::new()
  let required = detector.required_input().unwrap()
  assert_eq(required.position, 0)
  assert_eq(required.size, Some(32))
  // まだ判定していないので file_kind は None
  assert_eq(detector.file_kind(), None)
}

///|
test "detector is idempotent once detected" {
  let detector = @demux.Mp4FileKindDetector::new()
  feed_until_done(detector, kind_case("fixture:black-h264-video.mp4").input)
  assert_eq(detector.file_kind(), Some(@demux.Mp4FileKind::Mp4))
  assert_eq(detector.required_input(), None)
  // 終端状態に余計なデータを渡しても結果は変わらない
  detector.handle_input(@demux.Input::{ position: 9999, data: b"\x00\x00"[:], })
  assert_eq(detector.file_kind(), Some(@demux.Mp4FileKind::Mp4))
  assert_eq(detector.required_input(), None)
}

///|
test "fragmented mp4 is detected only via moov mvex" {
  let detector = @demux.Mp4FileKindDetector::new()
  feed_until_done(detector, kind_case("fixture:black-h264-fmp4.mp4").input)
  assert_eq(detector.file_kind(), Some(@demux.Mp4FileKind::FragmentedMp4))
  // moov が末尾にある配置でも同じ判定（拡張子・ブランドには依存しない）
  let detector = @demux.Mp4FileKindDetector::new()
  feed_until_done(detector, kind_case("moov_at_end_fmp4").input)
  assert_eq(detector.file_kind(), Some(@demux.Mp4FileKind::FragmentedMp4))
}

///|
test "unacceptable input latches an InvalidInput error" {
  let detector = @demux.Mp4FileKindDetector::new()
  // 要求位置(0)と一致しない位置からの入力は受理されない
  detector.handle_input(@demux.Input::{ position: 8, data: b"\x00"[:], })
  try detector.file_kind() catch {
    @demux.DecodeError(e) => {
      let @bytes.Mp4Error(kind~, reason~, ..) = e
      assert_true(kind == @bytes.InvalidInput)
      assert_true(reason.to_string().has_prefix("handle_input() error:"))
    }
    _ => abort("expected DecodeError")
  } noraise {
    _ => abort("expected error")
  }
  // エラー保持中はそれ以上の要求は出さない
  assert_eq(detector.required_input(), None)
}

///|
test "short input at the required position reports truncation" {
  let detector = @demux.Mp4FileKindDetector::new()
  // 要求位置(0)からの短い入力は「ファイルがそこで終わった」ものとして受理され
  // 個別のエラーとして報告される
  detector.handle_input(@demux.Input::{ position: 0, data: b"\x00\x01"[:], })
  try detector.file_kind() catch {
    @demux.DecodeError(e) => {
      let @bytes.Mp4Error(kind~, reason~, ..) = e
      assert_true(kind == @bytes.InvalidData)
      assert_eq(
        reason.to_string(),
        "input ended before the required range was available",
      )
    }
    _ => abort("expected DecodeError")
  } noraise {
    _ => abort("expected error")
  }
}

///|
test "moov box size beyond Int::max_value is rejected up front" {
  // 上流の `moov box size exceeds usize::MAX` に相当。
  // MoonBit ではバッファ長が Int なので Int::max_value を上限とする。
  let ftyp32 = b"\x00\x00\x00\x20ftypisom\x00\x00\x02\x00isomiso2mp41mp42"
  let moov_huge = b"\x00\x00\x00\x01moov\x00\x00\x00\x00\x80\x00\x00\x00" +
    Bytes::make(16, 0)
  let data = ftyp32 + moov_huge
  let detector = @demux.Mp4FileKindDetector::new()
  feed_until_done(detector, data)
  try detector.file_kind() catch {
    @demux.DecodeError(e) => {
      let @bytes.Mp4Error(kind~, reason~, ..) = e
      assert_true(kind == @bytes.InvalidData)
      assert_eq(reason.to_string(), "moov box size exceeds usize::MAX")
    }
    _ => abort("expected DecodeError")
  } noraise {
    _ => abort("expected error")
  }
}
