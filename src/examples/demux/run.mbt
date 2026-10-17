// demux CLI の Sans I/O demuxer 駆動ロジック。
// このパッケージだけがファイルシステムに触れる。`Mp4FileDemuxer` 自体は
// `required_input` が要求する絶対位置・サイズのレンジをこちらが供給する
// pull 型であり、上流 examples/demux.rs と同じ構成を取る。
//
// upstream との差異 (issue 0014 で確定):
// - upstream は `min(request_size, buf.len())` で 1MB バッファに切り詰めるが、
//   `size=Some(n)` の要求に対しては全レンジを満たすのが demuxer の契約。
//   本実装は上限 (--buffer-size、既定 1MiB) を超える `Some(n)` 要求を
//   `RequestTooLarge` として明示的に失敗させ、契約違反の入力を渡さない。
// - `size=None` の要求 (EOF までの box) は upstream 同様
//   `min(残り, 上限)` だけを供給する (is_satisfied_by が位置のみを要求するため)。
// - `handle_input` は raise しない (upstream 同様に内部蓄積される) ので、
//   demux エラーは `tracks()` / `next_sample()` の呼び出しで表面化する。

///|
/// 既定の読み取り上限 (upstream demux.rs の 1MB バッファ相当)。
pub const DEFAULT_BUFFER_SIZE : Int64 = 1048576

///|
/// 既定の表示サンプル数 (upstream demux.rs が先頭 10 件を表示するのに合わせる)。
pub const DEFAULT_MAX_SAMPLES : Int32 = 10

///|
/// demuxer を required_input 駆動で初期化済み状態まで進める。
/// 要求された絶対レンジを `file` から読み取って `handle_input` へ供給する。
async fn initialize(
  demuxer : @mp4_demux.Mp4FileDemuxer,
  file : @fs.File,
  file_size~ : Int64,
  max_read~ : Int64,
) -> Unit raise CliError {
  let max_read_u64 = max_read.reinterpret_as_uint64()
  while demuxer.required_input() is Some(required) {
    let position_i64 = required.position.reinterpret_as_int64()
    let remaining = if file_size > position_i64 {
      (file_size - position_i64).reinterpret_as_uint64()
    } else {
      0UL
    }
    let needed : UInt64 = match required.size {
      Some(size) => {
        if size > max_read_u64 {
          raise CliError::RequestTooLarge(
            position=required.position,
            size~,
            limit=max_read_u64,
          )
        }
        if size > remaining {
          raise CliError::UnexpectedEof(
            position=required.position,
            expected=size,
            got=remaining,
          )
        }
        size
      }
      None =>
        // EOF までの可変長要求: upstream と同じく上限まで読む
        if remaining < max_read_u64 {
          remaining
        } else {
          max_read_u64
        }
    }
    let data : Bytes = if needed == 0UL {
      b""
    } else {
      file.read_exactly_at(needed.to_int(), position=position_i64) catch {
        _ =>
          raise CliError::IoError(
            "failed to read \{needed} bytes at position \{required.position}",
          )
      }
    }
    demuxer.handle_input(@mp4_demux.Input::{
      position: required.position,
      data: data[:],
    })
  }
}

///|
/// MP4 ファイルを demux し、指定形式の出力文字列を返す。
/// 失敗時は `CliError` を raise する (終了コードは `CliError::exit_code`)。
pub async fn run(
  path~ : String,
  max_samples~ : Int32,
  max_read~ : Int64,
  json~ : Bool,
) -> String raise CliError {
  let file = @fs.open(path, mode=ReadOnly) catch {
    _ => raise CliError::IoError("cannot open file: \{path}")
  }
  let file_size = file.size() catch {
    _ => raise CliError::IoError("cannot stat file: \{path}")
  }
  defer file.close()
  let demuxer = @mp4_demux.Mp4FileDemuxer::new()
  initialize(demuxer, file, file_size~, max_read~)
  let tracks = demuxer.tracks() catch { e => raise CliError::Demux(e) }
  let samples : Array[@mp4_demux.Sample] = []
  while samples.length() < max_samples {
    let next = demuxer.next_sample() catch { e => raise CliError::Demux(e) }
    match next {
      Some(sample) => samples.push(sample)
      None => break
    }
  }
  // 上限ちょうどで止まった場合、さらにサンプルが残っているかだけを調べる
  let truncated = if samples.length() == max_samples {
    let probe = demuxer.next_sample() catch { e => raise CliError::Demux(e) }
    probe is Some(_)
  } else {
    false
  }
  if json {
    format_json(file=path, tracks, samples, truncated~)
  } else {
    format_text(tracks, samples, truncated~)
  }
}
