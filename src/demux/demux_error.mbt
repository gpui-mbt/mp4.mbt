///|
/// MP4 ファイルの復調処理中に発生し得るエラー。
///
/// 上流 `DemuxError` に対応する。
pub(all) suberror DemuxError {
  /// ボックスのデコード中にエラーが発生した
  DecodeError(@bytes.Mp4Error)
  /// サンプルテーブルの操作中にエラーが発生した
  SampleTableError(@boxes.SampleTableAccessorError)
  /// 不正な操作・状態に対してエラーが発生した
  ///
  /// ここでは「呼び出し側のライブラリの使い方に問題がある」場合にのみ
  /// 発生する。外部から与えられたデータ（MP4 ファイル）に由来するエラーは、
  /// このメンバーでは判定されない
  InvalidState(String)
  /// 処理を継続するためにはデータの入力が必要
  ///
  /// 構造としては、[`Mp4FileKindDetector::handle_input`] などで内部的にのみ
  /// 発生し、外部には見えない。ただし、上流同様に公開エラーとして残してある
  InputRequired(RequiredInput)
}

///|
/// 入力データの提供を要求する [`DemuxError`] を作る。
///
/// 上流 `DemuxError::input_required` に対応する。
pub fn DemuxError::input_required(
  position : UInt64,
  size : UInt64?,
) -> DemuxError {
  InputRequired(RequiredInput::{ position, size, })
}

///|
/// 上流 `Display for DemuxError` に対応する。
pub fn DemuxError::to_string(self : DemuxError) -> String {
  match self {
    DecodeError(e) => "Failed to decode MP4 box: \{e.to_string()}"
    SampleTableError(e) => "Sample table error: \{e.to_string()}"
    InvalidState(m) => m
    InputRequired(required) =>
      match required.size {
        Some(size) =>
          "Need input data: \{size} bytes at position \{required.position}"
        None =>
          "Need input data: from position \{required.position} to end of file"
      }
  }
}
