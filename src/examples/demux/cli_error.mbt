// demux CLI 固有のエラー型と終了コード。
// プロセスの終了コードは upstream の demux.rs にはない概念なので、
// このポート固有の規約としてここで固定する。

///|
/// CLI 固有エラーの分類。
pub(all) suberror CliError {
  /// 引数が不正 (argparse 失敗・値域外)
  Usage(String)
  /// ファイルのオープン / 読み取り失敗、予期しない EOF など
  IoError(String)
  /// required_input の要求サイズが許容上限を超過 (メモリ上限ポリシー)
  RequestTooLarge(position~ : UInt64, size~ : UInt64, limit~ : UInt64)
  /// required_input の要求範囲がファイル末尾を超過 (中途切断ファイル)
  UnexpectedEof(position~ : UInt64, expected~ : UInt64, got~ : UInt64)
  /// demuxer が報告したエラー (Mp4Error / SampleTableError / InvalidState)
  Demux(@mp4_demux.DemuxError)
}

///|
/// プロセス終了コード。
/// - 0: 正常終了
/// - 2: 引数不正
/// - 3: I/O エラー (オープン失敗・読み取り失敗・予期しない EOF)
/// - 4: required_input が読み取り上限を超過
/// - 5: demux エラー
pub fn CliError::exit_code(self : CliError) -> Int32 {
  match self {
    Usage(_) => 2
    IoError(_) | UnexpectedEof(..) => 3
    RequestTooLarge(..) => 4
    Demux(_) => 5
  }
}

///|
/// stderr 出力用の統一エラーメッセージ。
pub fn CliError::message(self : CliError) -> String {
  match self {
    Usage(msg) => msg
    IoError(msg) => msg
    RequestTooLarge(position~, size~, limit~) =>
      "required input range exceeds the read limit: position=\{position}, size=\{size}, limit=\{limit} (adjust --buffer-size)"
    UnexpectedEof(position~, expected~, got~) =>
      "unexpected end of file: position=\{position}, expected=\{expected} bytes, got=\{got} bytes"
    Demux(error) => demux_error_message(error)
  }
}

///|
/// DemuxError を人間可読な 1 行メッセージへ整形する。
fn demux_error_message(error : @mp4_demux.DemuxError) -> String {
  match error {
    @mp4_demux.DecodeError(@bytes.Mp4Error(kind~, reason~, ..)) => {
      let kind_name = kind.to_string()
      if reason.length() > 0 {
        "MP4 decode error (\{kind_name}): \{reason}"
      } else {
        "MP4 decode error (\{kind_name})"
      }
    }
    @mp4_demux.SampleTableError(e) => "sample table error: \{e.to_string()}"
    @mp4_demux.InvalidState(message) =>
      "demuxer is in an invalid state: \{message}"
    @mp4_demux.InputRequired(required) =>
      "demuxer requires more input at position \{required.position}"
  }
}
