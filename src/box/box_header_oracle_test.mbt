///|
/// Rust oracle の `error_kind_str` と同じ snake_case の分類名へ寄せる。
fn oracle_kind_name(kind : @bytes.ErrorKind) -> String {
  match kind {
    @bytes.ErrorKind::InvalidInput => "invalid_input"
    @bytes.ErrorKind::InvalidData => "invalid_data"
    @bytes.ErrorKind::InsufficientBuffer => "insufficient_buffer"
    @bytes.ErrorKind::Unsupported => "unsupported"
  }
}

///|
/// Rust oracle（`tools/oracle` の `box-headers` モード）と `@box.BoxHeader` の
/// 振る舞いをケース単位で突き合わせる差分テスト。
///
/// ケース表は `box_header_oracle_cases_test.mbt`（Rust oracle からの生成物）が
/// 持つ。成否・失敗分類・ボックス種別・サイズ表現・宣言サイズ・ヘッダー長・
/// ペイロード長・wire-preserving なヘッダー再エンコード結果・カーソル位置が
/// 一致することを要求する。
test "box header behaviour matches the Rust oracle case table" {
  if oracle_box_header_cases.is_empty() {
    fail("oracle case table is empty")
  }
  for case in oracle_box_header_cases {
    let cursor = @bytes.ReadCursor::new(case.input)
    let result = try
      Some(@box.BoxHeader::decode_header_and_payload(cursor))
    catch {
      @bytes.Mp4Error(kind~, ..) => {
        if case.ok {
          fail(
            "\{case.name}: oracle expects success, but failed with \{oracle_kind_name(kind)}",
          )
        }
        if oracle_kind_name(kind) != case.error_kind {
          fail(
            "\{case.name}: error kind mismatch: oracle=\{case.error_kind}, ours=\{oracle_kind_name(kind)}",
          )
        }
        if cursor.position() != 0 {
          fail(
            "\{case.name}: failed decode must roll back the cursor, but position=\{cursor.position()}",
          )
        }
        None
      }
    } noraise {
      result => result
    }
    match result {
      Some((header, payload)) => {
        if !case.ok {
          fail(
            "\{case.name}: oracle expects \{case.error_kind}, but decode succeeded",
          )
        }
        if header.box_type().as_bytes() != case.box_type {
          fail("\{case.name}: box_type mismatch")
        }
        let size_kind = match header.box_size() {
          @box.BoxSize::U32(_) => "u32"
          @box.BoxSize::U64(_) => "u64"
        }
        if size_kind != case.size_kind {
          fail(
            "\{case.name}: size kind mismatch: oracle=\{case.size_kind}, ours=\{size_kind}",
          )
        }
        if header.box_size().get() != case.size {
          fail("\{case.name}: size value mismatch")
        }
        if header.external_size() != case.external_size {
          fail("\{case.name}: external size mismatch")
        }
        if payload.length() != case.payload_size {
          fail("\{case.name}: payload size mismatch")
        }
        if @bytes.encode_to_bytes(header) != case.reencoded {
          fail("\{case.name}: re-encoded header must be wire-preserving")
        }
        if cursor.position() != case.external_size + case.payload_size {
          fail("\{case.name}: cursor must stop at the end of the payload")
        }
      }
      None => ()
    }
  }
}
