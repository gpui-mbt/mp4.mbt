// Native demux CLI のエントリポイント。
// upstream examples/demux.rs 相当: MP4 のパスを受け取り、track メタデータと
// 先頭サンプル一覧を表示する。I/O はこの実行パッケージだけが担当し、
// demuxer コア (gpui-mbt/mp4/demux) にはファイル系依存を持ち込まない。

///|
/// 終了コード制御のための libc exit。
extern "c" fn c_exit(code : Int32) = "exit"

///|
/// コマンドラインを構築する (テストでも再利用するため分離)。
fn build_command() -> @argparse.Command {
  @argparse.Command(
    "demux",
    about="Print track metadata and sample table of an MP4 file (Sans I/O Mp4FileDemuxer driver).",
    positionals=[@argparse.PositionArg("file", about="path to an MP4 file")],
    options=[
      @argparse.OptionArg(
        "max-samples",
        long="max-samples",
        about="maximum number of samples to print (default: 10)",
      ),
      @argparse.OptionArg(
        "buffer-size",
        long="buffer-size",
        about="maximum bytes read for a single required_input range (default: 1048576)",
      ),
    ],
    flags=[
      @argparse.FlagArg(
        "json",
        long="json",
        about="emit JSON instead of human-readable text",
      ),
    ],
  )
}

///|
/// `max-samples` 値を検証して Int へ変換する。
fn parse_positive_int(raw~ : String, name~ : String) -> Int32 raise CliError {
  let trimmed = raw.trim().to_owned()
  let parsed = @string.parse_int(trimmed) catch {
    _ => raise CliError::Usage("invalid \{name}: \{raw}")
  }
  if parsed < 0 {
    raise CliError::Usage(
      "invalid \{name}: \{raw} (must be a non-negative integer)",
    )
  }
  parsed
}

///|
/// `buffer-size` 値を検証して Int64 へ変換する。
/// Int 変換上限を超える値は巨大すぎるため拒否する。
fn parse_buffer_size(raw~ : String) -> Int64 raise CliError {
  let trimmed = raw.trim().to_owned()
  let parsed = @string.parse_int64(trimmed) catch {
    _ => raise CliError::Usage("invalid --buffer-size: \{raw}")
  }
  if parsed <= 0L {
    raise CliError::Usage(
      "invalid --buffer-size: \{raw} (must be a positive integer)",
    )
  }
  if parsed > 2147483647L {
    raise CliError::Usage(
      "invalid --buffer-size: \{raw} (must be at most 2147483647 bytes)",
    )
  }
  parsed
}

///|
/// パース結果から設定を組み立て、本体を実行して終了コードを返す。
async fn run_cli(argv~ : Array[String]) -> Int32 {
  let command = build_command()
  // @env.args() の先頭はプログラム名なので除いた残りをパースする
  let user_argv = if argv.length() > 1 { argv[1:] } else { argv[:] }
  let matches = command.parse(argv=user_argv) catch {
    _ => {
      @stdio.stderr.write(
        "error: invalid arguments\n\n\{command.render_help()}",
      )
      return 2
    }
  }
  let path = match matches.values.get("file") {
    Some([path, ..]) => path
    _ => {
      @stdio.stderr.write(
        "error: missing required argument <file>\n\n\{command.render_help()}",
      )
      return 2
    }
  }
  let max_samples = match matches.values.get("max-samples") {
    Some([raw, ..]) =>
      parse_positive_int(raw~, name="--max-samples") catch {
        CliError::Usage(msg) => {
          @stdio.stderr.write("error: \{msg}\n")
          return 2
        }
        e => raise e
      }
    _ => DEFAULT_MAX_SAMPLES
  }
  let max_read = match matches.values.get("buffer-size") {
    Some([raw, ..]) =>
      parse_buffer_size(raw~) catch {
        CliError::Usage(msg) => {
          @stdio.stderr.write("error: \{msg}\n")
          return 2
        }
        e => raise e
      }
    _ => DEFAULT_BUFFER_SIZE
  }
  let json = matches.flags.get("json") is Some(true)
  let output = run(path~, max_samples~, max_read~, json~) catch {
    e => {
      @stdio.stderr.write("error: \{e.message()}\n")
      return e.exit_code()
    }
  }
  @stdio.stdout.write(output) catch {
    _ => return 3
  }
  0
}

///|
async fn main {
  let code = run_cli(argv=@env.args())
  // stdout/stderr への書き込みをフラッシュしてから終了する
  c_exit(code)
}
