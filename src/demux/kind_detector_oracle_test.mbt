///|
/// `kind-detector-cases` が生成するケース 1 件分（生成データ用）。
///
/// `requests` は上流検出器が順に要求した入力範囲の列で、`mdat` のような
/// ペイロードを読み飛ばしていることをそのまま証明する。
priv struct OracleKindDetectorCase {
  name : String
  input : Bytes
  requests : Array[OracleKindDetectorRequest]
  outcome : String
  classification : String
  error_kind : String
  box_type : String
  reason : String
}

///|
/// oracle が記録した必須入力範囲 1 件分。
priv struct OracleKindDetectorRequest {
  position : UInt64
  size : UInt64?
}

///|
/// oracle の `input_at`（`data[position..]` を提供する呼び出し側）に対応する。
fn kind_input_at(data : Bytes, position : UInt64) -> @demux.Input {
  if position > data.length().to_uint64() {
    return @demux.Input::{ position, data: b""[:], }
  }
  @demux.Input::{ position, data: data[position.to_int():], }
}

///|
/// oracle の `run_kind_detector` に対応する。
/// 上流のドキュメント例と同じく `required_input()` が `None` になるまで
/// 要求位置からの残りを供給し、要求列と最終結果を返す。
fn drive_kind_detector(
  data : Bytes,
) -> (Array[@demux.RequiredInput], @demux.Mp4FileKind?, @demux.DemuxError?) {
  let detector = @demux.Mp4FileKindDetector::new()
  let requests : Array[@demux.RequiredInput] = []
  for _ in 0..<10000 {
    match detector.required_input() {
      Some(required) => {
        requests.push(required)
        detector.handle_input(kind_input_at(data, required.position))
      }
      None => break
    }
  }
  try detector.file_kind() catch {
    e => (requests, None, Some(e))
  } noraise {
    kind => (requests, kind, None)
  }
}

///|
/// oracle の `error_kind_str` に対応する。
fn oracle_kind_name(kind : @bytes.ErrorKind) -> String {
  match kind {
    InvalidInput => "invalid_input"
    InvalidData => "invalid_data"
    InsufficientBuffer => "insufficient_buffer"
    Unsupported => "unsupported"
  }
}

///|
test "kind detector matches the rust oracle" {
  inspect(oracle_kind_detector_cases.length() > 0, content="true")
  for case in oracle_kind_detector_cases {
    let (requests, kind, error) = drive_kind_detector(case.input)

    // 要求範囲の列が上流と一致すること（mdat のペイロードを要求しない証拠）
    assert_eq(requests.length(), case.requests.length())
    for i, req in requests.iter2() {
      assert_eq(req.position, case.requests[i].position)
      assert_eq(req.size, case.requests[i].size)
    }

    match case.outcome {
      "mp4" => {
        assert_true(error is None)
        assert_eq(kind, Some(@demux.Mp4FileKind::Mp4))
      }
      "fragmented_mp4" => {
        assert_true(error is None)
        assert_eq(kind, Some(@demux.Mp4FileKind::FragmentedMp4))
      }
      _ => {
        assert_true(kind is None)
        match error {
          Some(@demux.DecodeError(e)) => {
            let @bytes.Mp4Error(kind~, reason~, box_type~, ..) = e
            assert_eq(case.classification, "decode_error")
            assert_eq(oracle_kind_name(kind), case.error_kind)
            assert_eq(reason.to_string(), case.reason)
            let actual_box_type = match box_type {
              Some(t) => t.to_string()
              None => ""
            }
            assert_eq(actual_box_type, case.box_type)
          }
          Some(@demux.InvalidState(message)) => {
            assert_eq(case.classification, "invalid_state")
            assert_eq(message, case.reason)
          }
          Some(@demux.SampleTableError(_)) =>
            assert_eq(case.classification, "sample_table_error")
          Some(@demux.InputRequired(_)) =>
            assert_eq(case.classification, "input_required")
          None =>
            abort(
              "\{case.name}: oracle expected an error but moonbit succeeded",
            )
        }
      }
    }
  }
}
