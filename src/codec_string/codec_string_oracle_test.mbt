///|
/// Rust oracle の `codec-strings-cases` が返す 1 ケース分（生成データ用）。
///
/// 生成元は `src/codec_string/codec_string_oracle_cases_test.mbt`。
/// `decode_ok=false` の行はサンプルエントリー自体のデコードが失敗するケースで、
/// `codec_string` / `error_kind` / `reason` はそのデコードエラーを記録する。
struct OracleCodecStringCase {
  name : String
  input : Bytes
  decode_ok : Bool
  codec_string : String
  error_kind : String
  reason : String
}

///|
/// エラー分類を oracle の JSON と同じ snake_case 名にする。
fn codec_string_kind_name(kind : @bytes.ErrorKind) -> String {
  match kind {
    InvalidInput => "invalid_input"
    InvalidData => "invalid_data"
    InsufficientBuffer => "insufficient_buffer"
    Unsupported => "unsupported"
  }
}

///|
test "codec strings match the rust oracle case table" {
  inspect(oracle_codec_string_cases.length() > 0, content="true")
  for case in oracle_codec_string_cases {
    let cursor = @bytes.ReadCursor::new(case.input)
    let decoded : @boxes.SampleEntry? = try @bytes.decode_from(cursor) catch {
      @bytes.Mp4Error(kind~, reason~, ..) => {
        if case.decode_ok {
          fail(
            "\{case.name}: oracle decoded, but moonbit decode failed with \{codec_string_kind_name(kind)}: \{reason}",
          )
        }
        if codec_string_kind_name(kind) != case.error_kind {
          fail(
            "\{case.name}: oracle decode kind \{case.error_kind}, moonbit kind \{codec_string_kind_name(kind)} (\{reason})",
          )
        }
        if case.reason != "" && reason != case.reason {
          fail(
            "\{case.name}: oracle decode reason '\{case.reason}', moonbit reason '\{reason}'",
          )
        }
        None
      }
    } noraise {
      entry => Some(entry)
    }
    match decoded {
      None => if case.decode_ok { fail("\{case.name}: unreachable") }
      Some(entry) => {
        if !case.decode_ok {
          fail("\{case.name}: oracle decode failed, but moonbit succeeded")
        }
        let result : String? = try
          @codec_string.from_sample_entry(entry)
        catch {
          @bytes.Mp4Error(kind~, reason~, ..) => {
            if case.codec_string != "" {
              fail(
                "\{case.name}: oracle produced '\{case.codec_string}', but moonbit failed with \{codec_string_kind_name(kind)}: \{reason}",
              )
            }
            if codec_string_kind_name(kind) != case.error_kind {
              fail(
                "\{case.name}: oracle kind \{case.error_kind}, moonbit kind \{codec_string_kind_name(kind)} (\{reason})",
              )
            }
            if case.reason != "" && reason != case.reason {
              fail(
                "\{case.name}: oracle reason '\{case.reason}', moonbit reason '\{reason}'",
              )
            }
            None
          }
        } noraise {
          s => Some(s)
        }
        match result {
          Some(s) => {
            if case.codec_string == "" {
              fail(
                "\{case.name}: oracle failed with \{case.error_kind}, but moonbit produced '\{s}'",
              )
            }
            if s != case.codec_string {
              fail(
                "\{case.name}: oracle '\{case.codec_string}', moonbit '\{s}'",
              )
            }
          }
          None => ()
        }
      }
    }
  }
}
