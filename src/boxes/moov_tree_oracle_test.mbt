///|
/// Rust oracle の `moov` スナップショット 1 件分（生成データ用）。
///
/// 生成元は `src/boxes/moov_tree_oracle_cases_test.mbt`。
struct OracleMoovTreeCase {
  name : String
  input : Bytes
  ok : Bool
  snapshot : Array[String]
  error_kind : String
  reason : String
}

///|
/// Rust oracle が fixture から抽出した `moov` 1 件分（生成データ用）。
///
/// 生成元は `src/boxes/moov_tree_oracle_fixtures_test.mbt`。
struct OracleMoovTreeFixture {
  name : String
  moov : Bytes
  snapshot : Array[String]
}

///|
/// スナップショットの `*_hex` 用に `Bytes` を lowercase hex へ変換する。
fn moov_snapshot_hex(bytes : Bytes) -> String {
  let builder = StringBuilder()
  for i in 0..<bytes.length() {
    builder.write_string(bytes[i].to_hex())
  }
  builder.to_string()
}

///|
/// 16.16 固定小数点の生 4 バイトを hex にする。
fn moov_snapshot_fixed_16_16_hex(value : @bytes.FixedPointNumber) -> String {
  let cursor = @bytes.WriteCursor::new()
  cursor.write_fixed_16_16(value)
  moov_snapshot_hex(cursor.to_bytes())
}

///|
/// 8.8 固定小数点（符号あり整数部）の生 2 バイトを hex にする。
fn moov_snapshot_fixed_8_8_hex(value : @bytes.FixedPointNumber) -> String {
  let cursor = @bytes.WriteCursor::new()
  cursor.write_fixed_8_8(value)
  moov_snapshot_hex(cursor.to_bytes())
}

///|
/// 8.8 固定小数点（符号なし整数部）の生 2 バイトを hex にする。
fn moov_snapshot_fixed_8_8_unsigned_hex(
  value : @bytes.FixedPointNumber,
) -> String {
  let cursor = @bytes.WriteCursor::new()
  cursor.write_fixed_8_8_unsigned(value)
  moov_snapshot_hex(cursor.to_bytes())
}

///|
/// 行列 9 要素をカンマ区切りの十進にする。
fn moov_snapshot_matrix(matrix : Array[Int32]) -> String {
  let parts : Array[String] = []
  for value in matrix {
    parts.push(value.to_string())
  }
  parts.join(",")
}

///|
/// 真偽値を oracle と同じ `true` / `false` にする。
fn moov_snapshot_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
/// Rust oracle の `moov-tree` スナップショットと同じ行列を組み立てる。
///
/// 行の順序・書式は issue 0008 で凍結されている。変更すると
/// `src/boxes/moov_tree_oracle_cases_test.mbt` の期待値と一致しなくなる。
fn moov_snapshot(moov : @boxes.MoovBox) -> Array[String] {
  let lines : Array[String] = []
  let mvhd = moov.mvhd_box
  lines.push("moov.mvhd.creation_time=\{mvhd.creation_time.as_secs()}")
  lines.push("moov.mvhd.modification_time=\{mvhd.modification_time.as_secs()}")
  lines.push("moov.mvhd.timescale=\{mvhd.timescale.get()}")
  lines.push("moov.mvhd.duration=\{mvhd.duration}")
  lines.push("moov.mvhd.rate_hex=\{moov_snapshot_fixed_16_16_hex(mvhd.rate)}")
  lines.push("moov.mvhd.volume_hex=\{moov_snapshot_fixed_8_8_hex(mvhd.volume)}")
  lines.push("moov.mvhd.matrix=\{moov_snapshot_matrix(mvhd.matrix)}")
  lines.push("moov.mvhd.next_track_id=\{mvhd.next_track_id}")
  lines.push("moov.trak_count=\{moov.trak_boxes.length()}")
  for i in 0..<moov.trak_boxes.length() {
    let trak = moov.trak_boxes[i]
    let prefix = "trak[\{i}]"
    let tkhd = trak.tkhd_box
    lines.push(
      "\{prefix}.tkhd.enabled=\{moov_snapshot_bool(tkhd.flag_track_enabled)}",
    )
    lines.push(
      "\{prefix}.tkhd.in_movie=\{moov_snapshot_bool(tkhd.flag_track_in_movie)}",
    )
    lines.push(
      "\{prefix}.tkhd.in_preview=\{moov_snapshot_bool(tkhd.flag_track_in_preview)}",
    )
    lines.push(
      "\{prefix}.tkhd.size_is_aspect_ratio=\{moov_snapshot_bool(tkhd.flag_track_size_is_aspect_ratio)}",
    )
    lines.push("\{prefix}.tkhd.creation_time=\{tkhd.creation_time.as_secs()}")
    lines.push(
      "\{prefix}.tkhd.modification_time=\{tkhd.modification_time.as_secs()}",
    )
    lines.push("\{prefix}.tkhd.track_id=\{tkhd.track_id}")
    lines.push("\{prefix}.tkhd.duration=\{tkhd.duration}")
    lines.push("\{prefix}.tkhd.layer=\{tkhd.layer}")
    lines.push("\{prefix}.tkhd.alternate_group=\{tkhd.alternate_group}")
    lines.push(
      "\{prefix}.tkhd.volume_hex=\{moov_snapshot_fixed_8_8_hex(tkhd.volume)}",
    )
    lines.push("\{prefix}.tkhd.matrix=\{moov_snapshot_matrix(tkhd.matrix)}")
    lines.push(
      "\{prefix}.tkhd.width_hex=\{moov_snapshot_fixed_16_16_hex(tkhd.width)}",
    )
    lines.push(
      "\{prefix}.tkhd.height_hex=\{moov_snapshot_fixed_16_16_hex(tkhd.height)}",
    )
    lines.push(
      "\{prefix}.edts.present=\{moov_snapshot_bool(trak.edts_box is Some(_))}",
    )
    match trak.edts_box {
      Some(edts) =>
        match edts.elst_box {
          Some(elst) => {
            lines.push("\{prefix}.edts.elst_count=\{elst.entries.length()}")
            for j in 0..<elst.entries.length() {
              let entry = elst.entries[j]
              lines.push(
                "\{prefix}.edts.elst[\{j}].edit_duration=\{entry.edit_duration}",
              )
              lines.push(
                "\{prefix}.edts.elst[\{j}].media_time=\{entry.media_time}",
              )
              lines.push(
                "\{prefix}.edts.elst[\{j}].media_rate_hex=\{moov_snapshot_fixed_16_16_hex(entry.media_rate)}",
              )
            }
          }
          None => lines.push("\{prefix}.edts.elst_count=0")
        }
      None => ()
    }
    let mdia = trak.mdia_box
    let mdhd = mdia.mdhd_box
    lines.push(
      "\{prefix}.mdia.mdhd.creation_time=\{mdhd.creation_time.as_secs()}",
    )
    lines.push(
      "\{prefix}.mdia.mdhd.modification_time=\{mdhd.modification_time.as_secs()}",
    )
    lines.push("\{prefix}.mdia.mdhd.timescale=\{mdhd.timescale.get()}")
    lines.push("\{prefix}.mdia.mdhd.duration=\{mdhd.duration}")
    lines.push("\{prefix}.mdia.mdhd.language=\{mdhd.language.to_string()}")
    lines.push(
      "\{prefix}.mdia.hdlr.handler_type=\{mdia.hdlr_box.handler_type.to_string()}",
    )
    lines.push(
      "\{prefix}.mdia.hdlr.name_hex=\{moov_snapshot_hex(mdia.hdlr_box.name)}",
    )
    let minf = mdia.minf_box
    match minf.media_header {
      None => lines.push("\{prefix}.mdia.minf.media_header.type=none")
      Some(header) =>
        match header {
          @boxes.MediaHeader::Smhd(smhd) => {
            lines.push("\{prefix}.mdia.minf.media_header.type=smhd")
            lines.push(
              "\{prefix}.mdia.minf.media_header.balance_hex=\{moov_snapshot_fixed_8_8_unsigned_hex(smhd.balance)}",
            )
          }
          @boxes.MediaHeader::Vmhd(vmhd) => {
            lines.push("\{prefix}.mdia.minf.media_header.type=vmhd")
            lines.push(
              "\{prefix}.mdia.minf.media_header.opcolor=\{vmhd.opcolor[0]},\{vmhd.opcolor[1]},\{vmhd.opcolor[2]}",
            )
          }
          @boxes.MediaHeader::Sthd(_) =>
            lines.push("\{prefix}.mdia.minf.media_header.type=sthd")
          @boxes.MediaHeader::Nmhd(_) =>
            lines.push("\{prefix}.mdia.minf.media_header.type=nmhd")
        }
    }
    let dref = minf.dinf_box.dref_box
    match dref.url_box {
      None => lines.push("\{prefix}.mdia.minf.dinf.dref.url.present=false")
      Some(url) => {
        lines.push("\{prefix}.mdia.minf.dinf.dref.url.present=true")
        let self_contained = url.location is None
        lines.push(
          "\{prefix}.mdia.minf.dinf.dref.url.self_contained=\{moov_snapshot_bool(self_contained)}",
        )
        lines.push(
          "\{prefix}.mdia.minf.dinf.dref.url.location_none=\{moov_snapshot_bool(self_contained)}",
        )
        match url.location {
          Some(location) =>
            lines.push(
              "\{prefix}.mdia.minf.dinf.dref.url.location=\{location.get()}",
            )
          None => ()
        }
      }
    }
  }
  lines
}

///|
/// oracle の期待スナップショットと MoonBit 側の [`moov_snapshot`] を比較する。
///
/// 最初に食い違った行だけを報告する。
fn assert_moov_snapshot_matches_oracle(
  label : String,
  expected : Array[String],
  moov : @boxes.MoovBox,
) -> Unit raise {
  let actual = moov_snapshot(moov)
  if actual.length() != expected.length() {
    fail(
      "\{label}: snapshot line count differs (oracle=\{expected.length()}, moonbit=\{actual.length()})",
    )
  }
  for i in 0..<actual.length() {
    if actual[i] != expected[i] {
      fail(
        "\{label}: snapshot line \{i} differs (oracle=\{expected[i]}, moonbit=\{actual[i]})",
      )
    }
  }
}

///|
test "moov tree matches the rust oracle case table" {
  inspect(oracle_moov_tree_cases.length() > 0, content="true")
  for case in oracle_moov_tree_cases {
    let cursor = @bytes.ReadCursor::new(case.input)
    let decoded : @boxes.MoovBox? = try @bytes.decode_from(cursor) catch {
      @bytes.Mp4Error(kind~, reason~, ..) => {
        if case.ok {
          fail(
            "\{case.name}: oracle succeeded, but moonbit failed with \{oracle_kind_name(kind)}: \{reason}",
          )
        }
        if oracle_kind_name(kind) != case.error_kind {
          fail(
            "\{case.name}: oracle kind \{case.error_kind}, moonbit kind \{oracle_kind_name(kind)} (\{reason})",
          )
        }
        // upstream は insufficient_buffer に理由文を持たない（空文字列）ため、
        // oracle が理由文を持つエラー（invalid_input / invalid_data 系）だけ
        // 完全一致を要求する。kind はどの場合も一致を要求する。
        if case.reason != "" && reason != case.reason {
          fail(
            "\{case.name}: oracle reason '\{case.reason}', moonbit reason '\{reason}'",
          )
        }
        None
      }
    } noraise {
      moov => Some(moov)
    }
    match decoded {
      Some(moov) =>
        if case.ok {
          assert_moov_snapshot_matches_oracle(case.name, case.snapshot, moov)
        } else {
          fail(
            "\{case.name}: oracle failed with \{case.error_kind}, but moonbit succeeded",
          )
        }
      None => ()
    }
  }
}

///|
test "moov tree matches the rust oracle for extracted fixture moovs" {
  inspect(oracle_moov_tree_fixtures.length() > 0, content="true")
  for fixture in oracle_moov_tree_fixtures {
    let cursor = @bytes.ReadCursor::new(fixture.moov)
    let moov : @boxes.MoovBox = @bytes.decode_from(cursor)
    inspect(cursor.is_empty(), content="true")
    assert_moov_snapshot_matches_oracle(fixture.name, fixture.snapshot, moov)
  }
}
