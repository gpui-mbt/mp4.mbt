//! Deterministic Rust oracle for mp4.mbt compatibility golden generation.
//!
//! This tool runs the pinned upstream `shiguredo_mp4` (see `Cargo.toml`) and
//! prints a normalised JSON description of the result. The output is the
//! canonical golden used by the MoonBit candidate tests (see docs/upstream.md).
//!
//! Properties that matter for reproducibility:
//! - the upstream revision is pinned in `Cargo.toml`;
//! - no timestamps, randomness or absolute paths are included;
//! - all 64-bit integers are emitted as decimal strings so that JSON Number
//!   precision limits never round them;
//! - key order and formatting are fixed by this program.
//!
//! Usage: `mp4-oracle demux <mp4-file>`

use std::env;
use std::fmt::Write as _;
use std::fs;
use std::path::Path;
use std::process::ExitCode;

use shiguredo_mp4::aux::{SampleTableAccessor, SampleTableAccessorError};
use shiguredo_mp4::boxes::{
    MediaHeader, MoovBox, SampleEntry, StblBox,
    AudioSampleEntryFields, Avc1Box, AvccBox, DopsBox, OpusBox, StppBox,
    VisualSampleEntryFields,
};
use shiguredo_mp4::demux::{
    DemuxError, Input, Mp4FileDemuxer, Mp4FileKind, Mp4FileKindDetector, RequiredInput,
};
use shiguredo_mp4::mux::{Mp4FileMuxer, Mp4FileMuxerOptions};
use shiguredo_mp4::{
    BaseBox, BoxHeader, BoxSize, Decode, Encode, FixedPointNumber, LanguageCode, TrackKind, Uint,
    Utf8String,
};

mod oracle_json;

use oracle_json::*;

/// Pinned upstream revision (must match Cargo.toml and docs/upstream.md).
const UPSTREAM_SHA: &str = "1282b704f44184ec792e1549b5d31e0c4c54dc59";

/// Golden schema version. Bump when the normalised shape changes.
const SCHEMA_VERSION: u32 = 1;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("demux") if args.len() == 3 => match run_demux(&args[2]) {
            Ok(json) => {
                println!("{json}");
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("oracle error: {e}");
                ExitCode::FAILURE
            }
        },
        Some("box-headers") if args.len() == 2 => {
            println!("{}", run_box_headers());
            ExitCode::SUCCESS
        }
        Some("box-headers") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", box_header_moonbit_cases());
            ExitCode::SUCCESS
        }
        Some("box-tree") if args.len() == 3 => match run_box_tree(&args[2]) {
            Ok(json) => {
                println!("{json}");
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("oracle error: {e}");
                ExitCode::FAILURE
            }
        },
        Some("box-tree-cases") if args.len() == 2 => {
            println!("{}", run_box_tree_cases());
            ExitCode::SUCCESS
        }
        Some("box-tree-cases") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", box_tree_moonbit_cases());
            ExitCode::SUCCESS
        }
        Some("box-tree-fixtures") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", box_tree_moonbit_fixtures());
            ExitCode::SUCCESS
        }
        Some("moov-tree") if args.len() == 3 => match run_moov_tree(&args[2]) {
            Ok(json) => {
                println!("{json}");
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("oracle error: {e}");
                ExitCode::FAILURE
            }
        },
        Some("moov-tree-cases") if args.len() == 2 => {
            println!("{}", run_moov_tree_cases());
            ExitCode::SUCCESS
        }
        Some("moov-tree-cases") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", moov_tree_moonbit_cases());
            ExitCode::SUCCESS
        }
        Some("moov-tree-fixtures") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", moov_tree_moonbit_fixtures());
            ExitCode::SUCCESS
        }
        Some("sample-tables") if args.len() == 3 => match run_sample_tables(&args[2]) {
            Ok(json) => {
                println!("{json}");
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("oracle error: {e}");
                ExitCode::FAILURE
            }
        },
        Some("sample-tables-cases") if args.len() == 2 => {
            println!("{}", run_sample_table_cases());
            ExitCode::SUCCESS
        }
        Some("sample-tables-cases") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", sample_table_moonbit_cases());
            ExitCode::SUCCESS
        }
        Some("sample-tables-fixtures") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", sample_table_moonbit_fixtures());
            ExitCode::SUCCESS
        }
        Some("sample-entries") if args.len() == 3 => match run_sample_entries(&args[2]) {
            Ok(json) => {
                println!("{json}");
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("oracle error: {e}");
                ExitCode::FAILURE
            }
        },
        Some("sample-entries-cases") if args.len() == 2 => {
            println!("{}", run_sample_entry_cases());
            ExitCode::SUCCESS
        }
        Some("sample-entries-cases") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", sample_entry_moonbit_cases());
            ExitCode::SUCCESS
        }
        Some("sample-entries-fixtures") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", sample_entry_moonbit_fixtures());
            ExitCode::SUCCESS
        }
        Some("codec-strings-cases") if args.len() == 2 => {
            println!("{}", run_codec_string_cases());
            ExitCode::SUCCESS
        }
        Some("codec-strings-cases") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", codec_string_moonbit_cases());
            ExitCode::SUCCESS
        }
        Some("kind-detector-cases") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", kind_detector_moonbit_cases());
            ExitCode::SUCCESS
        }
        Some("demux-cases") if args.len() == 3 && args[2] == "--moonbit" => {
            print!("{}", demux_cases_moonbit());
            ExitCode::SUCCESS
        }
        _ => {
            eprintln!("usage: mp4-oracle demux <mp4-file>");
            eprintln!("       mp4-oracle box-headers");
            eprintln!("       mp4-oracle box-headers --moonbit");
            eprintln!("       mp4-oracle box-tree <mp4-file>");
            eprintln!("       mp4-oracle box-tree-cases");
            eprintln!("       mp4-oracle box-tree-cases --moonbit");
            eprintln!("       mp4-oracle box-tree-fixtures --moonbit");
            eprintln!("       mp4-oracle moov-tree <mp4-file>");
            eprintln!("       mp4-oracle moov-tree-cases");
            eprintln!("       mp4-oracle moov-tree-cases --moonbit");
            eprintln!("       mp4-oracle moov-tree-fixtures --moonbit");
            eprintln!("       mp4-oracle sample-tables <mp4-file>");
            eprintln!("       mp4-oracle sample-tables-cases");
            eprintln!("       mp4-oracle sample-tables-cases --moonbit");
            eprintln!("       mp4-oracle sample-tables-fixtures --moonbit");
            eprintln!("       mp4-oracle sample-entries <mp4-file>");
            eprintln!("       mp4-oracle sample-entries-cases");
            eprintln!("       mp4-oracle sample-entries-cases --moonbit");
            eprintln!("       mp4-oracle sample-entries-fixtures --moonbit");
            eprintln!("       mp4-oracle codec-strings-cases");
            eprintln!("       mp4-oracle codec-strings-cases --moonbit");
            eprintln!("       mp4-oracle kind-detector-cases --moonbit");
            eprintln!("       mp4-oracle demux-cases --moonbit");
            ExitCode::from(2)
        }
    }
}

fn run_demux(path: &str) -> Result<String, String> {
    let data = fs::read(path).map_err(|e| format!("failed to read {path}: {e}"))?;
    let name = Path::new(path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_owned();

    let mut input = String::from("{");
    input.push_str("\"name\": ");
    json_string(&name, &mut input);
    let _ = write!(input, ", \"size\": \"{}\", \"sha256\": ", data.len());
    json_string(&sha256_hex(&data), &mut input);
    input.push('}');

    let parts = [
        format!("  \"schema_version\": {SCHEMA_VERSION}"),
        format!("  \"upstream_sha\": \"{UPSTREAM_SHA}\""),
        format!("  \"input\": {input}"),
        format!("  \"kind\": {}", kind_json(&data)),
        format!("  \"tracks\": {}", tracks_json(&data)),
        format!("  \"samples\": {}", samples_json(&data)),
    ];
    Ok(format!("{{\n{}\n}}\n", parts.join(",\n")))
}

/// Minimal dependency-free SHA-256 (FIPS 180-4).
fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];
    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in msg.chunks_exact(64) {
        let mut w = [0u32; 64];
        for (i, word) in chunk.chunks_exact(4).enumerate() {
            w[i] = u32::from_be_bytes([word[0], word[1], word[2], word[3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }
        let mut a = h[0];
        let mut b = h[1];
        let mut c = h[2];
        let mut d = h[3];
        let mut e = h[4];
        let mut f = h[5];
        let mut g = h[6];
        let mut hh = h[7];
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = String::with_capacity(64);
    for v in h {
        let _ = write!(out, "{v:08x}");
    }
    out
}

/// Fixed `BoxHeader` boundary-case table shared with the MoonBit differential
/// test (`src/box/box_header_oracle_test.mbt`).
///
/// Changing this table changes the generated MoonBit case file; regenerate it
/// with `moon run tools/oracle/generate_box_header_cases.mbtx`.
const BOX_HEADER_CASES: &[(&str, &[u8])] = &[
    ("size8_mdat", b"\x00\x00\x00\x08mdat"),
    (
        "size16_payload",
        b"\x00\x00\x00\x10mdat\xAA\xBB\xCC\xDD\xEE\xFF\x00\x11",
    ),
    (
        "largesize24",
        b"\x00\x00\x00\x01mdat\x00\x00\x00\x00\x00\x00\x00\x18\x11\x11\x11\x11\x11\x11\x11\x11",
    ),
    ("size0_tail", b"\x00\x00\x00\x00mdat\xAA\xBB\xCC"),
    ("size0_header_only", b"\x00\x00\x00\x00free"),
    (
        "largesize0",
        b"\x00\x00\x00\x01mdat\x00\x00\x00\x00\x00\x00\x00\x00",
    ),
    ("size4_too_small", b"\x00\x00\x00\x04mdat"),
    ("size16_truncated", b"\x00\x00\x00\x10mdat\xAA\xBB"),
    (
        "largesize_missing",
        b"\x00\x00\x00\x01mdat\x00\x00\x00\x00\x00\x00\x00",
    ),
    (
        "uuid_largesize40",
        b"\x00\x00\x00\x01uuid\x6B\xC0\xA5\xA1\x8B\x2E\x4A\x71\xB0\x2C\xD0\x5B\x8B\x1B\x3F\x9F\x00\x00\x00\x00\x00\x00\x00\x28\x00\x01\x02\x03\x04\x05\x06\x07",
    ),
    (
        "uuid32",
        b"\x00\x00\x00\x20uuid\x6B\xC0\xA5\xA1\x8B\x2E\x4A\x71\xB0\x2C\xD0\x5B\x8B\x1B\x3F\x9F\x00\x00\x00\x00\x00\x00\x00\x08",
    ),
    (
        "uuid_missing_usertype",
        b"\x00\x00\x00\x20uuid\x6B\xC0\xA5\xA1\x8B\x2E\x4A\x71\xB0\x2C",
    ),
    (
        "unknown_control_fourcc",
        b"\x00\x00\x00\x0C\xFF\x00AB\x00\x01\x02\x03",
    ),
];

/// One row of the `BoxHeader` boundary-case table, normalised so that both the
/// JSON and MoonBit emitters describe exactly the same observation.
enum BoxHeaderOutcome {
    Ok {
        box_type: Vec<u8>,
        size_kind: &'static str,
        size: u64,
        external_size: usize,
        payload_size: usize,
        reencoded: Vec<u8>,
    },
    Err {
        error_kind: &'static str,
    },
}

fn box_header_outcome(input: &[u8]) -> BoxHeaderOutcome {
    match BoxHeader::decode_header_and_payload(input) {
        Ok((header, payload)) => {
            let (size_kind, size) = match header.box_size {
                BoxSize::U32(v) => ("u32", u64::from(v)),
                BoxSize::U64(v) => ("u64", v),
            };
            let mut buffer = vec![0u8; header.external_size()];
            let reencoded = match header.encode(&mut buffer) {
                Ok(n) => buffer[..n].to_vec(),
                Err(e) => panic!("header re-encode failed: {}", error_kind_str(e.kind)),
            };
            BoxHeaderOutcome::Ok {
                box_type: header.box_type.as_bytes().to_vec(),
                size_kind,
                size,
                external_size: header.external_size(),
                payload_size: payload.len(),
                reencoded,
            }
        }
        Err(error) => BoxHeaderOutcome::Err {
            error_kind: error_kind_str(error.kind),
        },
    }
}

/// Runs the fixed `BoxHeader` boundary-case table and emits the normalised
/// JSON consumed by the MoonBit differential test generator.
fn run_box_headers() -> String {
    let mut items: Vec<String> = Vec::new();
    for (name, input) in BOX_HEADER_CASES {
        items.push(box_header_case_json(name, input));
    }
    format!(
        "{{\"schema\": {SCHEMA_VERSION}, \"upstream_sha\": \"{UPSTREAM_SHA}\", \"cases\": [{}]}}",
        items.join(", ")
    )
}

fn box_header_case_json(name: &str, input: &[u8]) -> String {
    match box_header_outcome(input) {
        BoxHeaderOutcome::Ok {
            box_type,
            size_kind,
            size,
            external_size,
            payload_size,
            reencoded,
        } => format!(
            "{{\"name\": \"{name}\", \"input\": \"{}\", \"ok\": true, \"box_type\": \"{}\", \"size_kind\": \"{size_kind}\", \"size\": \"{size}\", \"external_size\": {}, \"payload_size\": {}, \"reencoded\": \"{}\"}}",
            hex(input),
            hex(&box_type),
            external_size,
            payload_size,
            hex(&reencoded),
        ),
        BoxHeaderOutcome::Err { error_kind } => format!(
            "{{\"name\": \"{name}\", \"input\": \"{}\", \"ok\": false, \"error_kind\": \"{error_kind}\"}}",
            hex(input)
        ),
    }
}

/// Emits the MoonBit case-table file consumed by
/// `src/box/box_header_oracle_test.mbt`.
///
/// The output is committed as `src/box/box_header_oracle_cases_test.mbt` and
/// compared byte for byte in CI (`moon fmt --check` also guards the format).
fn box_header_moonbit_cases() -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- box-headers --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (BOX_HEADER_CASES)."
    );
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(out, "// DO NOT EDIT MANUALLY. Regenerate:");
    let _ = writeln!(
        out,
        "//   cargo run --manifest-path tools/oracle/Cargo.toml -- box-headers --moonbit \\"
    );
    let _ = writeln!(out, "//     > src/box/box_header_oracle_cases_test.mbt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(out, "/// Rust oracle の `BoxHeader` 境界ケース 1 件分。");
    let _ = writeln!(out, "///");
    let _ = writeln!(
        out,
        "/// oracle の `box-headers` モード（固定ケース表）から生成される。手で編集しない。"
    );
    let _ = writeln!(out, "struct OracleBoxHeaderCase {{");
    for field in [
        "name : String",
        "input : Bytes",
        "ok : Bool",
        "box_type : Bytes",
        "size_kind : String",
        "size : UInt64",
        "external_size : Int32",
        "payload_size : Int32",
        "reencoded : Bytes",
        "error_kind : String",
    ] {
        let _ = writeln!(out, "  {field}");
    }
    let _ = writeln!(out, "}}");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `box-headers` が返すケース表（生成物）。"
    );
    let _ = writeln!(
        out,
        "let oracle_box_header_cases : Array[OracleBoxHeaderCase] = ["
    );
    for (name, input) in BOX_HEADER_CASES {
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: \"{name}\",");
        let _ = writeln!(out, "    input: {},", moonbit_bytes(input));
        match box_header_outcome(input) {
            BoxHeaderOutcome::Ok {
                box_type,
                size_kind,
                size,
                external_size,
                payload_size,
                reencoded,
            } => {
                let _ = writeln!(out, "    ok: true,");
                let _ = writeln!(out, "    box_type: {},", moonbit_bytes(&box_type));
                let _ = writeln!(out, "    size_kind: \"{size_kind}\",");
                let _ = writeln!(out, "    size: {size}UL,");
                let _ = writeln!(out, "    external_size: {external_size},");
                let _ = writeln!(out, "    payload_size: {payload_size},");
                let _ = writeln!(out, "    reencoded: {},", moonbit_bytes(&reencoded));
                let _ = writeln!(out, "    error_kind: \"\",");
            }
            BoxHeaderOutcome::Err { error_kind } => {
                let _ = writeln!(out, "    ok: false,");
                let _ = writeln!(out, "    box_type: b\"\",");
                let _ = writeln!(out, "    size_kind: \"\",");
                let _ = writeln!(out, "    size: 0UL,");
                let _ = writeln!(out, "    external_size: 0,");
                let _ = writeln!(out, "    payload_size: 0,");
                let _ = writeln!(out, "    reencoded: b\"\",");
                let _ = writeln!(out, "    error_kind: \"{error_kind}\",");
            }
        }
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}

/// Renders bytes as a MoonBit `b"..."` literal. Printable ASCII (except `"` and
/// `\`) stays literal; everything else becomes `\xNN`.
fn moonbit_bytes(data: &[u8]) -> String {
    let mut out = String::with_capacity(data.len() + 3);
    out.push_str("b\"");
    for &byte in data {
        if (0x20..=0x7e).contains(&byte) && byte != b'"' && byte != b'\\' {
            out.push(byte as char);
        } else {
            let _ = write!(out, "\\x{byte:02x}");
        }
    }
    out.push('"');
    out
}

/// Runs the header-level box-tree walk over a file and prints the golden JSON.
fn run_box_tree(path: &str) -> Result<String, String> {
    let data = fs::read(path).map_err(|e| format!("failed to read {path}: {e}"))?;
    let name = Path::new(path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_owned();

    let mut input = String::from("{");
    input.push_str("\"name\": ");
    json_string(&name, &mut input);
    let _ = write!(input, ", \"size\": \"{}\", \"sha256\": ", data.len());
    json_string(&sha256_hex(&data), &mut input);
    input.push('}');

    let parts = [
        format!("  \"schema_version\": {SCHEMA_VERSION}"),
        format!("  \"upstream_sha\": \"{UPSTREAM_SHA}\""),
        format!("  \"input\": {input}"),
        format!("  \"box_tree\": {}", box_tree_json(&data)),
    ];
    Ok(format!("{{\n{}\n}}\n", parts.join(",\n")))
}

/// Synthetic box-tree boundary cases shared with the MoonBit differential test
/// (`src/boxes/box_tree_oracle_test.mbt`).
///
/// Changing this table changes the generated MoonBit case file; regenerate it
/// with:
///   (cd tools/oracle && cargo run -- box-tree-cases --moonbit) \
///     > src/boxes/box_tree_oracle_cases_test.mbt
fn box_tree_cases() -> Vec<(&'static str, Vec<u8>)> {
    fn box_with(box_type: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let mut out = Vec::with_capacity(8 + payload.len());
        out.extend_from_slice(&((8 + payload.len()) as u32).to_be_bytes());
        out.extend_from_slice(box_type);
        out.extend_from_slice(payload);
        out
    }

    fn nested_box(box_type: &[u8; 4], levels: u32) -> Vec<u8> {
        let mut current = box_with(box_type, &[]);
        for _ in 1..levels {
            current = box_with(box_type, &current);
        }
        current
    }

    let mut ftyp = Vec::new();
    ftyp.extend_from_slice(b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomavc1");
    let mut ftyp_no_brands = Vec::new();
    ftyp_no_brands.extend_from_slice(b"\x00\x00\x00\x10ftypav01\x00\x00\x00\x00");
    let mut free = box_with(b"free", &[0x00, 0x00, 0x00, 0x00]);
    let mut mdat = box_with(b"mdat", &[0x11, 0x22, 0x33, 0x44]);

    vec![
        ("empty_input", Vec::new()),
        (
            "ftyp_free_mdat",
            {
                let mut v = ftyp.clone();
                v.append(&mut free);
                v.append(&mut mdat);
                v
            },
        ),
        ("ftyp_no_brands", ftyp_no_brands),
        ("unknown_top_level_size0", b"\x00\x00\x00\x00zzzz\xAA\xBB".to_vec()),
        ("unknown_top_level_size0_empty", b"\x00\x00\x00\x00zzzz".to_vec()),
        ("mdat_top_level_size0", b"\x00\x00\x00\x00mdat\x11\x22\x33".to_vec()),
        (
            "unknown_nested_size0",
            box_with(b"moov", b"\x00\x00\x00\x00zzzz"),
        ),
        (
            "unknown_nested_ok",
            box_with(b"moov", &box_with(b"zzzz", &[0xAA, 0xBB])),
        ),
        (
            "known_nested_size0_rejected",
            box_with(b"moov", b"\x00\x00\x00\x00free"),
        ),
        (
            "child_declared_size_below_header",
            box_with(b"moov", b"\x00\x00\x00\x04zzzz"),
        ),
        (
            "child_exceeds_parent",
            box_with(b"moov", b"\x00\x00\x00\x0Czzzz"),
        ),
        ("truncated_top_level_header", b"\x00\x00\x00\x10".to_vec()),
        (
            "moov_trak_mdia_nesting",
            box_with(b"moov", &box_with(b"trak", &box_with(b"mdia", &[]))),
        ),
        (
            "moov_empty_payload",
            b"\x00\x00\x00\x08moov".to_vec(),
        ),
        ("skip_unknown_top_level", b"\x00\x00\x00\x0Cskip\x00\x00\x00\x00".to_vec()),
        (
            "uuid_unknown_top_level",
            b"\x00\x00\x00\x20uuid\x6B\xC0\xA5\xA1\x8B\x2E\x4A\x71\xB0\x2C\xD0\x5B\x8B\x1B\x3F\x9F\x00\x00\x00\x00\x00\x00\x00\x08".to_vec(),
        ),
        (
            "free_largesize",
            b"\x00\x00\x00\x01free\x00\x00\x00\x00\x00\x00\x00\x14\x00\x00\x00\x00".to_vec(),
        ),
        (
            "free_payload_not_interpreted",
            box_with(b"free", &box_with(b"zzzz", &[0x01, 0x02])),
        ),
        (
            "unknown_largesize_nested",
            box_with(
                b"moov",
                b"\x00\x00\x00\x01zzzz\x00\x00\x00\x00\x00\x00\x00\x12\xAA\xBB",
            ),
        ),
        ("nested_beyond_depth_limit", nested_box(b"moov", 65)),
    ]
}

/// Runs the fixed box-tree case table and emits the normalised JSON.
fn run_box_tree_cases() -> String {
    let cases = box_tree_cases();
    let mut items: Vec<String> = Vec::new();
    for (name, input) in &cases {
        let mut entry = format!(
            "{{\"name\": \"{name}\", \"input\": \"{}\"",
            hex(input)
        );
        match walk_box_tree(input) {
            BoxTreeOutcome::Ok(nodes) => {
                let _ = write!(
                    entry,
                    ", \"ok\": true, \"nodes\": {}",
                    box_tree_nodes_json(&nodes)
                );
            }
            BoxTreeOutcome::Err(kind) => {
                let _ = write!(entry, ", \"ok\": false, \"error_kind\": \"{kind}\"");
            }
        }
        entry.push('}');
        items.push(entry);
    }
    format!(
        "{{\"schema\": {SCHEMA_VERSION}, \"upstream_sha\": \"{UPSTREAM_SHA}\", \"cases\": [{}]}}",
        items.join(", ")
    )
}

/// Emits the MoonBit case-table file consumed by
/// `src/boxes/box_tree_oracle_test.mbt`.
fn box_tree_moonbit_cases() -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- box-tree-cases --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (box_tree_cases)."
    );
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(
        out,
        "// DO NOT EDIT MANUALLY. Regenerate (canonical formatting is part of the file):"
    );
    let _ = writeln!(
        out,
        "//   (cd tools/oracle && cargo run -- box-tree-cases --moonbit) \\"
    );
    let _ = writeln!(out, "//     > src/boxes/box_tree_oracle_cases_test.mbt");
    let _ = writeln!(out, "//   moon fmt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `box-tree-cases` が返すケース表（生成物）。"
    );
    let _ = writeln!(
        out,
        "///"
    );
    let _ = writeln!(
        out,
        "/// 型は `src/boxes/box_tree_oracle_test.mbt` で定義する。手で編集しない。"
    );
    let _ = writeln!(
        out,
        "let oracle_box_tree_cases : Array[OracleBoxTreeCase] = ["
    );
    for (name, input) in &box_tree_cases() {
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: \"{name}\",");
        let _ = writeln!(out, "    input: {},", moonbit_bytes(input));
        match walk_box_tree(input) {
            BoxTreeOutcome::Ok(nodes) => {
                let _ = writeln!(out, "    ok: true,");
                let _ = writeln!(out, "    nodes: [");
                for node in &nodes {
                    write_moonbit_node(&mut out, node);
                }
                let _ = writeln!(out, "    ],");
                let _ = writeln!(out, "    error_kind: \"\",");
            }
            BoxTreeOutcome::Err(kind) => {
                let _ = writeln!(out, "    ok: false,");
                let _ = writeln!(out, "    nodes: [],");
                let _ = writeln!(out, "    error_kind: \"{kind}\",");
            }
        }
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}

fn write_moonbit_node(out: &mut String, node: &BoxTreeNode) {
    let _ = writeln!(out, "      {{");
    let _ = writeln!(out, "        depth: {},", node.depth);
    let _ = writeln!(out, "        box_type: {},", moonbit_bytes(&node.box_type));
    let _ = writeln!(out, "        start: {}UL,", node.start);
    let _ = writeln!(out, "        header_bytes: {},", node.header_bytes);
    let _ = writeln!(out, "        declared_size: {}UL,", node.declared_size);
    let _ = writeln!(out, "        total_size: {}UL,", node.total_size);
    let _ = writeln!(out, "      }},");
}

/// Fixtures embedded (with `include_bytes!`) in the generated MoonBit
/// differential test. The bytes are the checked-in upstream fixtures, so the
/// regenerated file changes exactly when a fixture changes.
const BOX_TREE_FIXTURES: &[(&str, &[u8])] = &[
    (
        "black-h264-video.mp4",
        include_bytes!("../../../tests/fixtures/upstream/black-h264-video.mp4"),
    ),
    (
        "black-h264-fmp4.mp4",
        include_bytes!("../../../tests/fixtures/upstream/black-h264-fmp4.mp4"),
    ),
];

/// Emits the fixture differential data consumed by
/// `src/boxes/box_tree_oracle_test.mbt`.
fn box_tree_moonbit_fixtures() -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- box-tree-fixtures --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (BOX_TREE_FIXTURES)."
    );
    let _ = writeln!(out, "// Fixtures (bytes embedded with include_bytes!):");
    for (name, data) in BOX_TREE_FIXTURES {
        let _ = writeln!(
            out,
            "//   {name} ({} bytes, sha256 {})",
            data.len(),
            sha256_hex(data)
        );
    }
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(
        out,
        "// DO NOT EDIT MANUALLY. Regenerate (canonical formatting is part of the file):"
    );
    let _ = writeln!(
        out,
        "//   (cd tools/oracle && cargo run -- box-tree-fixtures --moonbit) \\"
    );
    let _ = writeln!(out, "//     > src/boxes/box_tree_oracle_fixtures_test.mbt");
    let _ = writeln!(out, "//   moon fmt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `box-tree-fixtures` が返す fixture 走査（生成物）。"
    );
    let _ = writeln!(
        out,
        "///"
    );
    let _ = writeln!(
        out,
        "/// 型は `src/boxes/box_tree_oracle_test.mbt` で定義する。手で編集しない。"
    );
    let _ = writeln!(
        out,
        "let oracle_box_tree_fixtures : Array[OracleBoxTreeFixture] = ["
    );
    for (name, data) in BOX_TREE_FIXTURES {
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: \"{name}\",");
        let _ = writeln!(out, "    input: {},", moonbit_bytes(data));
        match walk_box_tree(data) {
            BoxTreeOutcome::Ok(nodes) => {
                let _ = writeln!(out, "    nodes: [");
                for node in &nodes {
                    write_moonbit_node(&mut out, node);
                }
                let _ = writeln!(out, "    ],");
            }
            BoxTreeOutcome::Err(kind) => {
                let _ = writeln!(
                    out,
                    "    nodes: [], // oracle walk failed: {kind}"
                );
            }
        }
        let _ = writeln!(out, "    ftyp: {},", ftyp_moonbit(data));
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}

/// Extracts one top-level box (header + payload) from a whole file.
///
/// Used by the `moov-tree` fixture generation to embed only the `moov` box of
/// the checked-in mp4 fixtures. Returns the upstream error kind/reason when
/// the file itself cannot be scanned, and `invalid_data`/`<type> box not
/// found` when the wanted box is absent.
fn extract_top_level_box(
    data: &[u8],
    wanted: &[u8; 4],
) -> Result<Vec<u8>, (&'static str, String)> {
    let mut rest = data;
    while !rest.is_empty() {
        let (header, payload) = BoxHeader::decode_header_and_payload(rest)
            .map_err(|e| (error_kind_str(e.kind), e.reason))?;
        let total = header.external_size() + payload.len();
        if header.box_type.as_bytes() == &wanted[..] {
            return Ok(rest[..total].to_vec());
        }
        rest = &rest[total..];
    }
    Err((
        "invalid_data",
        format!("{} box not found", String::from_utf8_lossy(wanted)),
    ))
}

/// One decoded moov tree observation: the frozen snapshot lines or the
/// upstream error that stopped the decode.
enum MoovTreeOutcome {
    Ok(Vec<String>),
    Err { kind: &'static str, reason: String },
}

fn moov_tree_outcome(input: &[u8]) -> MoovTreeOutcome {
    match MoovBox::decode(input) {
        Ok((moov, _)) => MoovTreeOutcome::Ok(moov_snapshot(&moov)),
        Err(error) => MoovTreeOutcome::Err {
            kind: error_kind_str(error.kind),
            reason: error.reason,
        },
    }
}

fn bool_str(value: bool) -> &'static str {
    if value {
        "true"
    } else {
        "false"
    }
}

fn lang_str(code: LanguageCode) -> String {
    String::from_utf8_lossy(&code.as_bytes()).into_owned()
}

fn handler_str(code: [u8; 4]) -> String {
    String::from_utf8_lossy(&code).into_owned()
}

fn matrix_str(matrix: &[i32; 9]) -> String {
    matrix
        .iter()
        .map(i32::to_string)
        .collect::<Vec<_>>()
        .join(",")
}

fn hex_16_16(value: &FixedPointNumber<i16, u16>) -> String {
    let mut bytes = Vec::with_capacity(4);
    bytes.extend_from_slice(&value.integer.to_be_bytes());
    bytes.extend_from_slice(&value.fraction.to_be_bytes());
    hex(&bytes)
}

fn hex_8_8(value: &FixedPointNumber<i8, u8>) -> String {
    hex(&[value.integer as u8, value.fraction])
}

fn hex_8_8_unsigned(value: &FixedPointNumber<u8, u8>) -> String {
    hex(&[value.integer, value.fraction])
}

fn hex_media_rate(value: &FixedPointNumber<i16, i16>) -> String {
    let mut bytes = Vec::with_capacity(4);
    bytes.extend_from_slice(&value.integer.to_be_bytes());
    bytes.extend_from_slice(&value.fraction.to_be_bytes());
    hex(&bytes)
}

/// Builds the flat `path=value` snapshot for a decoded `MoovBox`.
///
/// The line list is frozen by issue 0008 and must match `moov_snapshot` in
/// `src/boxes/moov_tree_oracle_test.mbt` line for line. 64-bit values are
/// decimal; raw field bytes are lowercase hex; fourcc/language values are the
/// raw characters.
fn moov_snapshot(moov: &MoovBox) -> Vec<String> {
    let mut lines = Vec::new();
    let mvhd = &moov.mvhd_box;
    lines.push(format!(
        "moov.mvhd.creation_time={}",
        mvhd.creation_time.as_secs()
    ));
    lines.push(format!(
        "moov.mvhd.modification_time={}",
        mvhd.modification_time.as_secs()
    ));
    lines.push(format!("moov.mvhd.timescale={}", mvhd.timescale.get()));
    lines.push(format!("moov.mvhd.duration={}", mvhd.duration));
    lines.push(format!("moov.mvhd.rate_hex={}", hex_16_16(&mvhd.rate)));
    lines.push(format!("moov.mvhd.volume_hex={}", hex_8_8(&mvhd.volume)));
    lines.push(format!("moov.mvhd.matrix={}", matrix_str(&mvhd.matrix)));
    lines.push(format!("moov.mvhd.next_track_id={}", mvhd.next_track_id));
    lines.push(format!("moov.trak_count={}", moov.trak_boxes.len()));

    for (i, trak) in moov.trak_boxes.iter().enumerate() {
        let tkhd = &trak.tkhd_box;
        lines.push(format!(
            "trak[{i}].tkhd.enabled={}",
            bool_str(tkhd.flag_track_enabled)
        ));
        lines.push(format!(
            "trak[{i}].tkhd.in_movie={}",
            bool_str(tkhd.flag_track_in_movie)
        ));
        lines.push(format!(
            "trak[{i}].tkhd.in_preview={}",
            bool_str(tkhd.flag_track_in_preview)
        ));
        lines.push(format!(
            "trak[{i}].tkhd.size_is_aspect_ratio={}",
            bool_str(tkhd.flag_track_size_is_aspect_ratio)
        ));
        lines.push(format!(
            "trak[{i}].tkhd.creation_time={}",
            tkhd.creation_time.as_secs()
        ));
        lines.push(format!(
            "trak[{i}].tkhd.modification_time={}",
            tkhd.modification_time.as_secs()
        ));
        lines.push(format!("trak[{i}].tkhd.track_id={}", tkhd.track_id));
        lines.push(format!("trak[{i}].tkhd.duration={}", tkhd.duration));
        lines.push(format!("trak[{i}].tkhd.layer={}", tkhd.layer));
        lines.push(format!(
            "trak[{i}].tkhd.alternate_group={}",
            tkhd.alternate_group
        ));
        lines.push(format!("trak[{i}].tkhd.volume_hex={}", hex_8_8(&tkhd.volume)));
        lines.push(format!("trak[{i}].tkhd.matrix={}", matrix_str(&tkhd.matrix)));
        lines.push(format!("trak[{i}].tkhd.width_hex={}", hex_16_16(&tkhd.width)));
        lines.push(format!(
            "trak[{i}].tkhd.height_hex={}",
            hex_16_16(&tkhd.height)
        ));

        lines.push(format!(
            "trak[{i}].edts.present={}",
            bool_str(trak.edts_box.is_some())
        ));
        if let Some(edts) = &trak.edts_box {
            lines.push(format!(
                "trak[{i}].edts.elst_count={}",
                edts.elst_box.as_ref().map(|e| e.entries.len()).unwrap_or(0)
            ));
            if let Some(elst) = &edts.elst_box {
                for (j, entry) in elst.entries.iter().enumerate() {
                    lines.push(format!(
                        "trak[{i}].edts.elst[{j}].edit_duration={}",
                        entry.edit_duration
                    ));
                    lines.push(format!(
                        "trak[{i}].edts.elst[{j}].media_time={}",
                        entry.media_time
                    ));
                    lines.push(format!(
                        "trak[{i}].edts.elst[{j}].media_rate_hex={}",
                        hex_media_rate(&entry.media_rate)
                    ));
                }
            }
        }

        let mdia = &trak.mdia_box;
        let mdhd = &mdia.mdhd_box;
        lines.push(format!(
            "trak[{i}].mdia.mdhd.creation_time={}",
            mdhd.creation_time.as_secs()
        ));
        lines.push(format!(
            "trak[{i}].mdia.mdhd.modification_time={}",
            mdhd.modification_time.as_secs()
        ));
        lines.push(format!(
            "trak[{i}].mdia.mdhd.timescale={}",
            mdhd.timescale.get()
        ));
        lines.push(format!("trak[{i}].mdia.mdhd.duration={}", mdhd.duration));
        lines.push(format!(
            "trak[{i}].mdia.mdhd.language={}",
            lang_str(mdhd.language)
        ));
        lines.push(format!(
            "trak[{i}].mdia.hdlr.handler_type={}",
            handler_str(mdia.hdlr_box.handler_type)
        ));
        lines.push(format!(
            "trak[{i}].mdia.hdlr.name_hex={}",
            hex(&mdia.hdlr_box.name)
        ));

        let minf = &mdia.minf_box;
        match &minf.media_header {
            None => lines.push(format!("trak[{i}].mdia.minf.media_header.type=none")),
            Some(MediaHeader::Smhd(b)) => {
                lines.push(format!("trak[{i}].mdia.minf.media_header.type=smhd"));
                lines.push(format!(
                    "trak[{i}].mdia.minf.media_header.balance_hex={}",
                    hex_8_8_unsigned(&b.balance)
                ));
            }
            Some(MediaHeader::Vmhd(b)) => {
                lines.push(format!("trak[{i}].mdia.minf.media_header.type=vmhd"));
                lines.push(format!(
                    "trak[{i}].mdia.minf.media_header.opcolor={},{},{}",
                    b.opcolor[0], b.opcolor[1], b.opcolor[2]
                ));
            }
            Some(MediaHeader::Sthd(_)) => {
                lines.push(format!("trak[{i}].mdia.minf.media_header.type=sthd"));
            }
            Some(MediaHeader::Nmhd(_)) => {
                lines.push(format!("trak[{i}].mdia.minf.media_header.type=nmhd"));
            }
        }

        match &minf.dinf_box.dref_box.url_box {
            None => lines.push(format!("trak[{i}].mdia.minf.dinf.dref.url.present=false")),
            Some(url) => {
                lines.push(format!("trak[{i}].mdia.minf.dinf.dref.url.present=true"));
                let self_contained = url.location.is_none();
                lines.push(format!(
                    "trak[{i}].mdia.minf.dinf.dref.url.self_contained={}",
                    bool_str(self_contained)
                ));
                lines.push(format!(
                    "trak[{i}].mdia.minf.dinf.dref.url.location_none={}",
                    bool_str(self_contained)
                ));
                if let Some(location) = &url.location {
                    lines.push(format!(
                        "trak[{i}].mdia.minf.dinf.dref.url.location={}",
                        location.get()
                    ));
                }
            }
        }
    }
    lines
}

fn snapshot_json(lines: &[String]) -> String {
    let items: Vec<String> = lines.iter().map(|line| json_string_to(line)).collect();
    format!("[{}]", items.join(", "))
}

fn moov_tree_json(input: &[u8]) -> String {
    match moov_tree_outcome(input) {
        MoovTreeOutcome::Ok(snapshot) => format!(
            "{{\"status\": \"ok\", \"snapshot\": {}}}",
            snapshot_json(&snapshot)
        ),
        MoovTreeOutcome::Err { kind, reason } => format!(
            "{{\"status\": \"error\", \"error_kind\": \"{kind}\", \"reason\": {}}}",
            json_string_to(&reason)
        ),
    }
}

/// Runs the `moov` decode over a whole file, extracting the top-level box.
fn moov_tree_json_for_file(data: &[u8]) -> String {
    match extract_top_level_box(data, b"moov") {
        Ok(moov) => moov_tree_json(&moov),
        Err((kind, reason)) => format!(
            "{{\"status\": \"error\", \"error_kind\": \"{kind}\", \"reason\": {}}}",
            json_string_to(&reason)
        ),
    }
}

/// Runs the `moov` tree snapshot over a whole mp4 file and prints the golden
/// JSON.
fn run_moov_tree(path: &str) -> Result<String, String> {
    let data = fs::read(path).map_err(|e| format!("failed to read {path}: {e}"))?;
    let name = Path::new(path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_owned();

    let mut input = String::from("{");
    input.push_str("\"name\": ");
    json_string(&name, &mut input);
    let _ = write!(input, ", \"size\": \"{}\", \"sha256\": ", data.len());
    json_string(&sha256_hex(&data), &mut input);
    input.push('}');

    let parts = [
        format!("  \"schema_version\": {SCHEMA_VERSION}"),
        format!("  \"upstream_sha\": \"{UPSTREAM_SHA}\""),
        format!("  \"input\": {input}"),
        format!("  \"moov_tree\": {}", moov_tree_json_for_file(&data)),
    ];
    Ok(format!("{{\n{}\n}}\n", parts.join(",\n")))
}

/// Fixed whole-`moov`-box case table shared with the MoonBit differential
/// test (`src/boxes/moov_tree_oracle_test.mbt`).
///
/// Success cases always contain a minimal valid `stbl` because the upstream
/// `MinfBox` requires it; issue 0008 does not type `stbl` on the MoonBit side
/// yet (see docs/upstream.md).
///
/// Changing this table changes the generated MoonBit case file; regenerate it
/// with:
///   (cd tools/oracle && cargo run -- moov-tree-cases --moonbit) \
///     > src/boxes/moov_tree_oracle_cases_test.mbt
fn moov_tree_cases() -> Vec<(&'static str, Vec<u8>)> {
    const DEFAULT_MATRIX: [i32; 9] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000];

    fn raw_box(box_type: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let mut out = Vec::with_capacity(8 + payload.len());
        out.extend_from_slice(&((8 + payload.len()) as u32).to_be_bytes());
        out.extend_from_slice(box_type);
        out.extend_from_slice(payload);
        out
    }

    fn full_box(box_type: &[u8; 4], version: u8, flags: u32, body: &[u8]) -> Vec<u8> {
        let mut payload = Vec::with_capacity(4 + body.len());
        payload.push(version);
        payload.extend_from_slice(&(flags & 0x00FF_FFFF).to_be_bytes()[1..]);
        payload.extend_from_slice(body);
        raw_box(box_type, &payload)
    }

    fn mvhd_box(
        v1: bool,
        creation_time: u64,
        modification_time: u64,
        timescale: u32,
        duration: u64,
        rate: (i16, u16),
        volume: (i8, u8),
        next_track_id: u32,
    ) -> Vec<u8> {
        let mut body = Vec::new();
        if v1 {
            body.extend_from_slice(&creation_time.to_be_bytes());
            body.extend_from_slice(&modification_time.to_be_bytes());
            body.extend_from_slice(&timescale.to_be_bytes());
            body.extend_from_slice(&duration.to_be_bytes());
        } else {
            body.extend_from_slice(&(creation_time as u32).to_be_bytes());
            body.extend_from_slice(&(modification_time as u32).to_be_bytes());
            body.extend_from_slice(&timescale.to_be_bytes());
            body.extend_from_slice(&(duration as u32).to_be_bytes());
        }
        body.extend_from_slice(&rate.0.to_be_bytes());
        body.extend_from_slice(&rate.1.to_be_bytes());
        body.extend_from_slice(&[volume.0 as u8, volume.1]);
        body.extend_from_slice(&[0u8; 2 + 8]);
        for value in DEFAULT_MATRIX {
            body.extend_from_slice(&value.to_be_bytes());
        }
        body.extend_from_slice(&[0u8; 4 * 6]);
        body.extend_from_slice(&next_track_id.to_be_bytes());
        full_box(b"mvhd", u8::from(v1), 0, &body)
    }

    #[allow(clippy::too_many_arguments)]
    fn tkhd_box(
        v1: bool,
        flags: u32,
        creation_time: u64,
        modification_time: u64,
        track_id: u32,
        duration: u64,
        layer: i16,
        alternate_group: i16,
        volume: (i8, u8),
        width: (i16, u16),
        height: (i16, u16),
    ) -> Vec<u8> {
        let mut body = Vec::new();
        if v1 {
            body.extend_from_slice(&creation_time.to_be_bytes());
            body.extend_from_slice(&modification_time.to_be_bytes());
        } else {
            body.extend_from_slice(&(creation_time as u32).to_be_bytes());
            body.extend_from_slice(&(modification_time as u32).to_be_bytes());
        }
        body.extend_from_slice(&track_id.to_be_bytes());
        body.extend_from_slice(&[0u8; 4]);
        if v1 {
            body.extend_from_slice(&duration.to_be_bytes());
        } else {
            body.extend_from_slice(&(duration as u32).to_be_bytes());
        }
        body.extend_from_slice(&[0u8; 4 * 2]);
        body.extend_from_slice(&layer.to_be_bytes());
        body.extend_from_slice(&alternate_group.to_be_bytes());
        body.extend_from_slice(&[volume.0 as u8, volume.1]);
        body.extend_from_slice(&[0u8; 2]);
        for value in DEFAULT_MATRIX {
            body.extend_from_slice(&value.to_be_bytes());
        }
        body.extend_from_slice(&width.0.to_be_bytes());
        body.extend_from_slice(&width.1.to_be_bytes());
        body.extend_from_slice(&height.0.to_be_bytes());
        body.extend_from_slice(&height.1.to_be_bytes());
        full_box(b"tkhd", u8::from(v1), flags, &body)
    }

    fn pack_language(code: &[u8; 3]) -> u16 {
        let mut packed: u16 = 0;
        for &byte in code {
            packed = (packed << 5) | u16::from(byte - 0x60);
        }
        packed
    }

    fn mdhd_box(
        v1: bool,
        creation_time: u64,
        modification_time: u64,
        timescale: u32,
        duration: u64,
        language: &[u8; 3],
    ) -> Vec<u8> {
        let mut body = Vec::new();
        if v1 {
            body.extend_from_slice(&creation_time.to_be_bytes());
            body.extend_from_slice(&modification_time.to_be_bytes());
            body.extend_from_slice(&timescale.to_be_bytes());
            body.extend_from_slice(&duration.to_be_bytes());
        } else {
            body.extend_from_slice(&(creation_time as u32).to_be_bytes());
            body.extend_from_slice(&(modification_time as u32).to_be_bytes());
            body.extend_from_slice(&timescale.to_be_bytes());
            body.extend_from_slice(&(duration as u32).to_be_bytes());
        }
        body.extend_from_slice(&pack_language(language).to_be_bytes());
        body.extend_from_slice(&[0u8; 2]);
        full_box(b"mdhd", u8::from(v1), 0, &body)
    }

    fn hdlr_box(handler_type: &[u8; 4], name: &[u8]) -> Vec<u8> {
        let mut body = Vec::new();
        body.extend_from_slice(&[0u8; 4]);
        body.extend_from_slice(handler_type);
        body.extend_from_slice(&[0u8; 4 * 3]);
        body.extend_from_slice(name);
        full_box(b"hdlr", 0, 0, &body)
    }

    fn elst_box(v1: bool, entries: &[(u64, i64)]) -> Vec<u8> {
        let mut body = Vec::new();
        body.extend_from_slice(&(entries.len() as u32).to_be_bytes());
        for (edit_duration, media_time) in entries {
            if v1 {
                body.extend_from_slice(&edit_duration.to_be_bytes());
                body.extend_from_slice(&media_time.to_be_bytes());
            } else {
                body.extend_from_slice(&(*edit_duration as u32).to_be_bytes());
                body.extend_from_slice(&(*media_time as i32).to_be_bytes());
            }
            body.extend_from_slice(&1i16.to_be_bytes());
            body.extend_from_slice(&0i16.to_be_bytes());
        }
        full_box(b"elst", u8::from(v1), 0, &body)
    }

    fn edts_box(elst: Option<Vec<u8>>) -> Vec<u8> {
        let mut payload = Vec::new();
        if let Some(elst) = elst {
            payload.extend(elst);
        }
        raw_box(b"edts", &payload)
    }

    fn url_box(self_contained: bool, location: Option<&str>) -> Vec<u8> {
        let mut body = Vec::new();
        if let Some(location) = location {
            body.extend_from_slice(location.as_bytes());
            body.push(0);
        }
        full_box(b"url ", 0, u32::from(self_contained), &body)
    }

    fn url_box_raw(flags: u32, body: &[u8]) -> Vec<u8> {
        full_box(b"url ", 0, flags, body)
    }

    fn dref_box(entries: &[Vec<u8>]) -> Vec<u8> {
        let mut body = Vec::new();
        body.extend_from_slice(&(entries.len() as u32).to_be_bytes());
        for entry in entries {
            body.extend_from_slice(entry);
        }
        full_box(b"dref", 0, 0, &body)
    }

    fn dinf_local_file() -> Vec<u8> {
        raw_box(b"dinf", &dref_box(&[url_box(true, None)]))
    }

    fn vmhd_box(graphicsmode: u16, opcolor: [u16; 3]) -> Vec<u8> {
        let mut body = Vec::new();
        body.extend_from_slice(&graphicsmode.to_be_bytes());
        for value in opcolor {
            body.extend_from_slice(&value.to_be_bytes());
        }
        full_box(b"vmhd", 0, 1, &body)
    }

    fn smhd_box(balance: (u8, u8)) -> Vec<u8> {
        full_box(b"smhd", 0, 0, &[balance.0, balance.1, 0, 0])
    }

    fn sthd_box() -> Vec<u8> {
        full_box(b"sthd", 0, 0, &[])
    }

    fn nmhd_box() -> Vec<u8> {
        full_box(b"nmhd", 0, 0, &[])
    }

    /// Minimal `stbl` accepted by the upstream sample-table decoder
    /// (empty `stsd`/`stts`/`stsc`/`stsz`/`stco`).
    fn stbl_min() -> Vec<u8> {
        let mut payload = Vec::new();
        payload.extend_from_slice(&raw_box(b"stsd", &[0u8; 8]));
        payload.extend_from_slice(&raw_box(b"stts", &[0u8; 8]));
        payload.extend_from_slice(&raw_box(b"stsc", &[0u8; 8]));
        payload.extend_from_slice(&raw_box(b"stsz", &[0u8; 12]));
        payload.extend_from_slice(&raw_box(b"stco", &[0u8; 8]));
        raw_box(b"stbl", &payload)
    }

    fn minf_box(
        media_header: Option<Vec<u8>>,
        dinf: Option<Vec<u8>>,
        stbl: Option<Vec<u8>>,
        extras: &[Vec<u8>],
    ) -> Vec<u8> {
        let mut payload = Vec::new();
        if let Some(media_header) = media_header {
            payload.extend(media_header);
        }
        if let Some(dinf) = dinf {
            payload.extend(dinf);
        }
        if let Some(stbl) = stbl {
            payload.extend(stbl);
        }
        for extra in extras {
            payload.extend_from_slice(extra);
        }
        raw_box(b"minf", &payload)
    }

    fn mdia_box(
        mdhd: Option<Vec<u8>>,
        hdlr: Option<Vec<u8>>,
        minf: Option<Vec<u8>>,
        extras: &[Vec<u8>],
    ) -> Vec<u8> {
        let mut payload = Vec::new();
        if let Some(mdhd) = mdhd {
            payload.extend(mdhd);
        }
        if let Some(hdlr) = hdlr {
            payload.extend(hdlr);
        }
        if let Some(minf) = minf {
            payload.extend(minf);
        }
        for extra in extras {
            payload.extend_from_slice(extra);
        }
        raw_box(b"mdia", &payload)
    }

    fn trak_box(
        tkhd: Option<Vec<u8>>,
        edts: Option<Vec<u8>>,
        mdia: Option<Vec<u8>>,
        extras: &[Vec<u8>],
    ) -> Vec<u8> {
        let mut payload = Vec::new();
        if let Some(tkhd) = tkhd {
            payload.extend(tkhd);
        }
        if let Some(edts) = edts {
            payload.extend(edts);
        }
        if let Some(mdia) = mdia {
            payload.extend(mdia);
        }
        for extra in extras {
            payload.extend_from_slice(extra);
        }
        raw_box(b"trak", &payload)
    }

    fn moov_box(mvhd: Option<Vec<u8>>, traks: &[Vec<u8>], extras: &[Vec<u8>]) -> Vec<u8> {
        let mut payload = Vec::new();
        if let Some(mvhd) = mvhd {
            payload.extend(mvhd);
        }
        for trak in traks {
            payload.extend_from_slice(trak);
        }
        for extra in extras {
            payload.extend_from_slice(extra);
        }
        raw_box(b"moov", &payload)
    }

    let mvhd_v0 = |duration: u64| {
        mvhd_box(false, 0, 0, 1000, duration, (1, 0), (1, 0), 1)
    };
    let mvhd_v1 = || {
        mvhd_box(
            true,
            4_294_967_296,
            4_294_967_297,
            1000,
            4_294_967_298,
            (1, 0),
            (1, 0),
            2,
        )
    };

    let video_mdia = |media_header: Vec<u8>| {
        mdia_box(
            Some(mdhd_box(false, 0, 0, 12800, 25600, b"eng")),
            Some(hdlr_box(b"vide", b"VideoHandler")),
            Some(minf_box(
                Some(media_header),
                Some(dinf_local_file()),
                Some(stbl_min()),
                &[],
            )),
            &[],
        )
    };
    let video_tkhd = |flags: u32| {
        tkhd_box(
            false,
            flags,
            0,
            0,
            1,
            1000,
            0,
            0,
            (0, 0),
            (1920, 0),
            (1080, 0),
        )
    };

    let mut cases: Vec<(&'static str, Vec<u8>)> = Vec::new();
    cases.push(("minimal_v0", moov_box(Some(mvhd_v0(2000)), &[], &[])));
    cases.push(("minimal_v1", moov_box(Some(mvhd_v1()), &[], &[])));
    cases.push((
        "zero_tracks_unknown_extras",
        moov_box(
            Some(mvhd_v0(2000)),
            &[],
            &[
                raw_box(b"mvex", &[]),
                raw_box(b"zzzz", &[0xAA]),
                raw_box(b"free", &[0, 1, 2, 3]),
            ],
        ),
    ));
    cases.push((
        "video_track_vmhd",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                None,
                Some(video_mdia(vmhd_box(64, [0x1000, 0x8000, 0xFFFF]))),
                &[raw_box(b"zzzz", &[0xAA, 0xBB])],
            )],
            &[],
        ),
    ));
    cases.push((
        "audio_track_smhd",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(tkhd_box(
                    false,
                    0b1,
                    0,
                    0,
                    2,
                    1000,
                    0,
                    0,
                    (1, 0),
                    (0, 0),
                    (0, 0),
                )),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 44100, 88200, b"jpn")),
                    Some(hdlr_box(b"soun", b"SoundHandler")),
                    Some(minf_box(
                        Some(smhd_box((0, 0x80))),
                        Some(dinf_local_file()),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "subtitle_track_sthd",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(tkhd_box(
                    false,
                    0b1,
                    0,
                    0,
                    3,
                    1000,
                    0,
                    0,
                    (0, 0),
                    (0, 0),
                    (0, 0),
                )),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 1000, 1000, b"und")),
                    Some(hdlr_box(b"subt", b"")),
                    Some(minf_box(
                        Some(sthd_box()),
                        Some(dinf_local_file()),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "text_track_nmhd",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(tkhd_box(
                    false,
                    0b1,
                    0,
                    0,
                    4,
                    1000,
                    0,
                    0,
                    (0, 0),
                    (0, 0),
                    (0, 0),
                )),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 1000, 1000, b"und")),
                    Some(hdlr_box(b"text", b"")),
                    Some(minf_box(
                        Some(nmhd_box()),
                        Some(dinf_local_file()),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "media_header_none",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b1)),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 12800, 25600, b"eng")),
                    Some(hdlr_box(b"vide", b"")),
                    Some(minf_box(
                        None,
                        Some(dinf_local_file()),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "two_tracks_mixed_versions",
        moov_box(
            Some(mvhd_v1()),
            &[
                trak_box(
                    Some(video_tkhd(0b11)),
                    Some(edts_box(Some(elst_box(false, &[(100, 0)])))),
                    Some(video_mdia(vmhd_box(0, [0, 0, 0]))),
                    &[],
                ),
                trak_box(
                    Some(tkhd_box(
                        true,
                        0b1,
                        4_294_967_296,
                        4_294_967_297,
                        2,
                        4_294_967_298,
                        -1,
                        -2,
                        (1, 0x80),
                        (1920, 0x8000),
                        (1080, 0x4000),
                    )),
                    Some(edts_box(Some(elst_box(true, &[(4_294_967_297, -1)])))),
                    Some(mdia_box(
                        Some(mdhd_box(
                            true,
                            4_294_967_296,
                            4_294_967_297,
                            44100,
                            4_294_967_298,
                            b"jpn",
                        )),
                        Some(hdlr_box(b"soun", b"SoundHandler")),
                        Some(minf_box(
                            Some(smhd_box((0, 0x80))),
                            Some(dinf_local_file()),
                            Some(stbl_min()),
                            &[],
                        )),
                        &[],
                    )),
                    &[],
                ),
            ],
            &[],
        ),
    ));
    cases.push((
        "edts_without_elst",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                Some(edts_box(None)),
                Some(video_mdia(vmhd_box(0, [0, 0, 0]))),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "elst_empty_v0",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                Some(edts_box(Some(elst_box(false, &[])))),
                Some(video_mdia(vmhd_box(0, [0, 0, 0]))),
                &[],
            )],
            &[],
        ),
    ));
    let dinf_url_location =
        raw_box(b"dinf", &dref_box(&[url_box(false, Some("https://example.com/media"))]));
    cases.push((
        "url_location",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 12800, 25600, b"eng")),
                    Some(hdlr_box(b"vide", b"")),
                    Some(minf_box(
                        Some(vmhd_box(0, [0, 0, 0])),
                        Some(dinf_url_location.clone()),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    let dinf_url_self_contained =
        raw_box(b"dinf", &dref_box(&[url_box_raw(1, b"ignored\x00")]));
    cases.push((
        "url_self_contained",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 12800, 25600, b"eng")),
                    Some(hdlr_box(b"vide", b"")),
                    Some(minf_box(
                        Some(vmhd_box(0, [0, 0, 0])),
                        Some(dinf_url_self_contained),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    let url_case = |raw_url: Vec<u8>| {
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 12800, 25600, b"eng")),
                    Some(hdlr_box(b"vide", b"")),
                    Some(minf_box(
                        Some(vmhd_box(0, [0, 0, 0])),
                        Some(raw_box(b"dinf", &dref_box(&[raw_url]))),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        )
    };
    cases.push(("url_missing_nul", url_case(url_box_raw(0, b"abc"))));
    cases.push((
        "url_invalid_utf8",
        url_case(url_box_raw(0, &[0xFF, 0xFE, 0x00])),
    ));
    cases.push(("missing_mvhd", moov_box(None, &[], &[])));
    cases.push((
        "missing_tkhd",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                None,
                None,
                Some(video_mdia(vmhd_box(0, [0, 0, 0]))),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "missing_mdia",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(Some(video_tkhd(0b11)), None, None, &[])],
            &[],
        ),
    ));
    cases.push((
        "missing_mdhd",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                None,
                Some(mdia_box(
                    None,
                    Some(hdlr_box(b"vide", b"")),
                    Some(minf_box(
                        Some(vmhd_box(0, [0, 0, 0])),
                        Some(dinf_local_file()),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "missing_hdlr",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 12800, 25600, b"eng")),
                    None,
                    Some(minf_box(
                        Some(vmhd_box(0, [0, 0, 0])),
                        Some(dinf_local_file()),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "missing_minf",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 12800, 25600, b"eng")),
                    Some(hdlr_box(b"vide", b"")),
                    None,
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "missing_dinf",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 12800, 25600, b"eng")),
                    Some(hdlr_box(b"vide", b"")),
                    Some(minf_box(
                        Some(vmhd_box(0, [0, 0, 0])),
                        None,
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "missing_dref",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 12800, 25600, b"eng")),
                    Some(hdlr_box(b"vide", b"")),
                    Some(minf_box(
                        Some(vmhd_box(0, [0, 0, 0])),
                        Some(raw_box(b"dinf", &[])),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "mvhd_timescale_zero",
        moov_box(
            Some(mvhd_box(false, 0, 0, 0, 2000, (1, 0), (1, 0), 1)),
            &[],
            &[],
        ),
    ));
    cases.push((
        "mdhd_timescale_zero",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 0, 0, b"eng")),
                    Some(hdlr_box(b"vide", b"")),
                    Some(minf_box(
                        Some(vmhd_box(0, [0, 0, 0])),
                        Some(dinf_local_file()),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "duplicate_mvhd",
        moov_box(
            Some(mvhd_v0(2000)),
            &[],
            &[mvhd_box(false, 0, 0, 1000, 3000, (1, 0), (1, 0), 9)],
        ),
    ));
    cases.push((
        "duplicate_media_header",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b11)),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 12800, 25600, b"eng")),
                    Some(hdlr_box(b"vide", b"")),
                    Some(minf_box(
                        Some(vmhd_box(0, [0, 0, 0])),
                        Some(dinf_local_file()),
                        Some(stbl_min()),
                        &[smhd_box((0, 0))],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "hdlr_name_raw",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(video_tkhd(0b1)),
                None,
                Some(mdia_box(
                    Some(mdhd_box(false, 0, 0, 1000, 1000, b"und")),
                    Some(hdlr_box(b"zzzz", &[0x00, 0xFF, 0x61])),
                    Some(minf_box(
                        Some(vmhd_box(0, [0, 0, 0])),
                        Some(dinf_local_file()),
                        Some(stbl_min()),
                        &[],
                    )),
                    &[],
                )),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "tkhd_flag_bits_and_fractions",
        moov_box(
            Some(mvhd_v0(2000)),
            &[trak_box(
                Some(tkhd_box(
                    false,
                    0b1111,
                    0,
                    0,
                    7,
                    1000,
                    -1,
                    -2,
                    (0, 0x80),
                    (1920, 0x8000),
                    (1080, 0x4000),
                )),
                None,
                Some(video_mdia(vmhd_box(0, [0, 0, 0]))),
                &[],
            )],
            &[],
        ),
    ));
    cases.push((
        "truncated_child",
        b"\x00\x00\x00\x10moov\x00\x00\x00\x14mvhd".to_vec(),
    ));
    cases.push((
        "mvhd_short_payload",
        moov_box(Some(raw_box(b"mvhd", &[0, 0, 0, 0])), &[], &[]),
    ));
    cases
}

/// Runs the fixed moov-tree case table and emits the normalised JSON.
fn run_moov_tree_cases() -> String {
    let cases = moov_tree_cases();
    let mut items: Vec<String> = Vec::new();
    for (name, input) in &cases {
        let mut entry = format!("{{\"name\": \"{name}\", \"input\": \"{}\"", hex(input));
        match moov_tree_outcome(input) {
            MoovTreeOutcome::Ok(snapshot) => {
                let _ = write!(
                    entry,
                    ", \"ok\": true, \"snapshot\": {}",
                    snapshot_json(&snapshot)
                );
            }
            MoovTreeOutcome::Err { kind, reason } => {
                let _ = write!(
                    entry,
                    ", \"ok\": false, \"error_kind\": \"{kind}\", \"reason\": {}",
                    json_string_to(&reason)
                );
            }
        }
        entry.push('}');
        items.push(entry);
    }
    format!(
        "{{\"schema\": {SCHEMA_VERSION}, \"upstream_sha\": \"{UPSTREAM_SHA}\", \"cases\": [{}]}}",
        items.join(", ")
    )
}

/// Renders a string as a MoonBit string literal.
fn moonbit_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 || c as u32 == 0x7F => {
                let _ = write!(out, "\\u{{{:x}}}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Writes a `snapshot: [...]` struct field at the given indentation.
fn write_moonbit_snapshot(out: &mut String, snapshot: &[String], indent: usize) {
    let pad = " ".repeat(indent);
    let _ = writeln!(out, "{pad}snapshot: [");
    for line in snapshot {
        let _ = writeln!(out, "{pad}  {},", moonbit_string(line));
    }
    let _ = writeln!(out, "{pad}],");
}

/// Emits the MoonBit case-table file consumed by
/// `src/boxes/moov_tree_oracle_test.mbt`.
fn moov_tree_moonbit_cases() -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- moov-tree-cases --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (moov_tree_cases)."
    );
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(
        out,
        "// DO NOT EDIT MANUALLY. Regenerate (canonical formatting is part of the file):"
    );
    let _ = writeln!(
        out,
        "//   (cd tools/oracle && cargo run -- moov-tree-cases --moonbit) \\"
    );
    let _ = writeln!(out, "//     > src/boxes/moov_tree_oracle_cases_test.mbt");
    let _ = writeln!(out, "//   moon fmt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `moov-tree-cases` が返すケース表（生成物）。"
    );
    let _ = writeln!(out, "///");
    let _ = writeln!(
        out,
        "/// 型は `src/boxes/moov_tree_oracle_test.mbt` で定義する。手で編集しない。"
    );
    let _ = writeln!(
        out,
        "let oracle_moov_tree_cases : Array[OracleMoovTreeCase] = ["
    );
    for (name, input) in &moov_tree_cases() {
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: \"{name}\",");
        let _ = writeln!(out, "    input: {},", moonbit_bytes(input));
        match moov_tree_outcome(input) {
            MoovTreeOutcome::Ok(snapshot) => {
                let _ = writeln!(out, "    ok: true,");
                write_moonbit_snapshot(&mut out, &snapshot, 4);
                let _ = writeln!(out, "    error_kind: \"\",");
                let _ = writeln!(out, "    reason: \"\",");
            }
            MoovTreeOutcome::Err { kind, reason } => {
                let _ = writeln!(out, "    ok: false,");
                let _ = writeln!(out, "    snapshot: [],");
                let _ = writeln!(out, "    error_kind: \"{kind}\",");
                let _ = writeln!(out, "    reason: {},", moonbit_string(&reason));
            }
        }
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}

/// Fixtures embedded (with `include_bytes!`) in the generated MoonBit
/// differential test. The generated data embeds only the extracted top-level
/// `moov` box, so it changes exactly when a fixture (or its moov) changes.
const MOOV_TREE_FIXTURES: &[(&str, &[u8])] = &[
    (
        "black-h264-video.mp4",
        include_bytes!("../../../tests/fixtures/upstream/black-h264-video.mp4"),
    ),
    (
        "black-h264-fmp4.mp4",
        include_bytes!("../../../tests/fixtures/upstream/black-h264-fmp4.mp4"),
    ),
];

/// Extracts the top-level `moov` box of every fixture (panics on failure:
/// generation must not silently emit stale data).
fn moov_tree_fixture_moovs() -> Vec<(&'static str, Vec<u8>)> {
    MOOV_TREE_FIXTURES
        .iter()
        .map(|(name, data)| {
            let moov = extract_top_level_box(data, b"moov").unwrap_or_else(|(kind, reason)| {
                panic!("{name}: top-level moov extraction failed: {kind}: {reason}")
            });
            (*name, moov)
        })
        .collect()
}

/// Emits the fixture differential data consumed by
/// `src/boxes/moov_tree_oracle_test.mbt`.
fn moov_tree_moonbit_fixtures() -> String {
    let fixtures = moov_tree_fixture_moovs();
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- moov-tree-fixtures --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (MOOV_TREE_FIXTURES)."
    );
    let _ = writeln!(
        out,
        "// Fixtures (top-level `moov` box extracted from the checked-in mp4):"
    );
    for (name, moov) in &fixtures {
        let _ = writeln!(
            out,
            "//   {name}: moov {} bytes, sha256 {}",
            moov.len(),
            sha256_hex(moov)
        );
    }
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(
        out,
        "// DO NOT EDIT MANUALLY. Regenerate (canonical formatting is part of the file):"
    );
    let _ = writeln!(
        out,
        "//   (cd tools/oracle && cargo run -- moov-tree-fixtures --moonbit) \\"
    );
    let _ = writeln!(out, "//     > src/boxes/moov_tree_oracle_fixtures_test.mbt");
    let _ = writeln!(out, "//   moon fmt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `moov-tree-fixtures` が返す fixture 走査（生成物）。"
    );
    let _ = writeln!(out, "///");
    let _ = writeln!(
        out,
        "/// 型は `src/boxes/moov_tree_oracle_test.mbt` で定義する。手で編集しない。"
    );
    let _ = writeln!(
        out,
        "let oracle_moov_tree_fixtures : Array[OracleMoovTreeFixture] = ["
    );
    for (name, moov) in &fixtures {
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: \"{name}\",");
        let _ = writeln!(out, "    moov: {},", moonbit_bytes(moov));
        let snapshot = match moov_tree_outcome(moov) {
            MoovTreeOutcome::Ok(snapshot) => snapshot,
            MoovTreeOutcome::Err { kind, reason } => {
                panic!("{name}: extracted moov decode failed: {kind}: {reason}")
            }
        };
        write_moonbit_snapshot(&mut out, &snapshot, 4);
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}

/// Renders the upstream `FtypBox` fields as MoonBit data (or `None`).
fn ftyp_moonbit(data: &[u8]) -> String {
    if data.len() < 8 || &data[4..8] != b"ftyp" {
        return "None".to_owned();
    }
    match shiguredo_mp4::boxes::FtypBox::decode(data) {
        Ok((ftyp, _)) => {
            let brands: Vec<String> = ftyp
                .compatible_brands
                .iter()
                .map(|b| moonbit_bytes(&b.get()))
                .collect();
            format!(
                "Some({{ major_brand: {}, minor_version: {}U, compatible_brands: [{}] }})",
                moonbit_bytes(&ftyp.major_brand.get()),
                ftyp.minor_version,
                brands.join(", "),
            )
        }
        Err(_) => "None".to_owned(),
    }
}

// ---------------------------------------------------------------------------
// sample-tables: `stbl` boxes and `SampleTableAccessor`
// ---------------------------------------------------------------------------

/// One decoded sample-table observation: the frozen snapshot lines (including
/// accessor error lines) or the decode error that stopped `StblBox::decode`.
enum SampleTableOutcome {
    Ok(Vec<String>),
    DecodeErr { kind: &'static str, reason: String },
}

/// Decodes one whole `stbl` box, builds the upstream accessor and snapshots it.
fn sample_table_outcome(input: &[u8]) -> SampleTableOutcome {
    match StblBox::decode(input) {
        Ok((stbl, _)) => SampleTableOutcome::Ok(match SampleTableAccessor::new(stbl) {
            Ok(accessor) => sample_table_snapshot(&accessor),
            Err(error) => accessor_error_lines(&error),
        }),
        Err(error) => SampleTableOutcome::DecodeErr {
            kind: error_kind_str(error.kind),
            reason: error.reason,
        },
    }
}

/// Builds the frozen `sample-tables` snapshot for a constructed accessor.
///
/// The line list is frozen by issue 0009 and must match
/// `sample_table_snapshot` in `src/boxes/sample_table_oracle_test.mbt` line for
/// line: counts first, then every chunk in order, then every sample in order.
/// `sample[<i>]` / `chunk[<i>]` use 0-based loop indices while `.index=` is the
/// 1-based value from the accessor; 64-bit values are decimal.
fn sample_table_snapshot(accessor: &SampleTableAccessor<StblBox>) -> Vec<String> {
    let mut lines = Vec::new();
    lines.push(format!("sample_count={}", accessor.sample_count()));
    lines.push(format!("chunk_count={}", accessor.chunk_count()));
    for (i, chunk) in accessor.chunks().enumerate() {
        lines.push(format!("chunk[{i}].index={}", chunk.index().get()));
        lines.push(format!("chunk[{i}].offset={}", chunk.offset()));
        lines.push(format!("chunk[{i}].sample_count={}", chunk.sample_count()));
        lines.push(format!(
            "chunk[{i}].sample_entry_index={}",
            chunk.sample_entry_index()
        ));
    }
    for (i, sample) in accessor.samples().enumerate() {
        lines.push(format!("sample[{i}].index={}", sample.index().get()));
        lines.push(format!("sample[{i}].timestamp={}", sample.timestamp()));
        lines.push(format!("sample[{i}].duration={}", sample.duration()));
        lines.push(format!("sample[{i}].data_offset={}", sample.data_offset()));
        lines.push(format!("sample[{i}].data_size={}", sample.data_size()));
        lines.push(format!(
            "sample[{i}].sync={}",
            bool_str(sample.is_sync_sample())
        ));
        match sample.composition_time_offset() {
            Some(offset) => lines.push(format!("sample[{i}].cto={offset}")),
            None => lines.push(format!("sample[{i}].cto=none")),
        }
        lines.push(format!(
            "sample[{i}].chunk_index={}",
            sample.chunk().index().get()
        ));
    }
    lines
}

/// Builds the frozen `error=accessor` lines for a failed
/// `SampleTableAccessor::new`: the variant name followed by one line per field,
/// named exactly like the variant field (values are the upstream numbers;
/// `box_type` uses `BoxType`'s display).
fn accessor_error_lines(error: &SampleTableAccessorError) -> Vec<String> {
    use SampleTableAccessorError as E;

    let mut lines = vec![String::from("error=accessor")];
    match error {
        E::InconsistentSampleCount {
            stts_sample_count,
            other_box_type,
            other_sample_count,
        } => {
            lines.push(String::from("error.variant=InconsistentSampleCount"));
            lines.push(format!("stts_sample_count={stts_sample_count}"));
            lines.push(format!("other_box_type={other_box_type}"));
            lines.push(format!("other_sample_count={other_sample_count}"));
        }
        E::FirstChunkIndexIsNotOne { actual_chunk_index } => {
            lines.push(String::from("error.variant=FirstChunkIndexIsNotOne"));
            lines.push(format!("actual_chunk_index={}", actual_chunk_index.get()));
        }
        E::LastChunkIndexIsTooLarge {
            max_chunk_index,
            last_chunk_index,
        } => {
            lines.push(String::from("error.variant=LastChunkIndexIsTooLarge"));
            lines.push(format!("max_chunk_index={}", max_chunk_index.get()));
            lines.push(format!("last_chunk_index={}", last_chunk_index.get()));
        }
        E::MissingSampleEntry {
            stsc_entry_index,
            sample_description_index,
            sample_entry_count,
        } => {
            lines.push(String::from("error.variant=MissingSampleEntry"));
            lines.push(format!("stsc_entry_index={stsc_entry_index}"));
            lines.push(format!(
                "sample_description_index={}",
                sample_description_index.get()
            ));
            lines.push(format!("sample_entry_count={sample_entry_count}"));
        }
        E::ChunkIndicesNotMonotonicallyIncreasing => {
            lines.push(String::from(
                "error.variant=ChunkIndicesNotMonotonicallyIncreasing",
            ));
        }
        E::ChunksExistButNoSamples { chunk_count } => {
            lines.push(String::from("error.variant=ChunksExistButNoSamples"));
            lines.push(format!("chunk_count={chunk_count}"));
        }
        E::SampleCountOverflow {
            box_type,
            accumulated_sample_count,
            entry_sample_count,
        } => {
            lines.push(String::from("error.variant=SampleCountOverflow"));
            lines.push(format!("box_type={box_type}"));
            lines.push(format!(
                "accumulated_sample_count={accumulated_sample_count}"
            ));
            lines.push(format!("entry_sample_count={entry_sample_count}"));
        }
        E::SampleDataOffsetOverflow {
            sample_index,
            accumulated_offset,
            sample_data_size,
        } => {
            lines.push(String::from("error.variant=SampleDataOffsetOverflow"));
            lines.push(format!("sample_index={}", sample_index.get()));
            lines.push(format!("accumulated_offset={accumulated_offset}"));
            lines.push(format!("sample_data_size={sample_data_size}"));
        }
    }
    lines
}

/// Runs the `stbl` decode + accessor snapshot over every track of an mp4 file
/// and prints the golden JSON.
///
/// `sample_tables` holds one entry per track (`status: "ok"` with the snapshot
/// lines; accessor errors are embedded as `error=accessor` lines). A missing or
/// malformed `moov` yields an empty array and describes the failure in
/// `moov_error` instead.
fn run_sample_tables(path: &str) -> Result<String, String> {
    let data = fs::read(path).map_err(|e| format!("failed to read {path}: {e}"))?;
    let name = Path::new(path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_owned();

    let mut input = String::from("{");
    input.push_str("\"name\": ");
    json_string(&name, &mut input);
    let _ = write!(input, ", \"size\": \"{}\", \"sha256\": ", data.len());
    json_string(&sha256_hex(&data), &mut input);
    input.push('}');

    let (tables, moov_error) = match extract_top_level_box(&data, b"moov") {
        Ok(moov) => match MoovBox::decode(&moov) {
            Ok((moov_box, _)) => (sample_tables_json_for_moov(&moov_box), String::from("null")),
            Err(error) => (
                String::from("[]"),
                format!(
                    "{{\"error_kind\": \"{}\", \"reason\": {}}}",
                    error_kind_str(error.kind),
                    json_string_to(&error.reason)
                ),
            ),
        },
        Err((kind, reason)) => (
            String::from("[]"),
            format!(
                "{{\"error_kind\": \"{kind}\", \"reason\": {}}}",
                json_string_to(&reason)
            ),
        ),
    };

    let parts = [
        format!("  \"schema_version\": {SCHEMA_VERSION}"),
        format!("  \"upstream_sha\": \"{UPSTREAM_SHA}\""),
        format!("  \"input\": {input}"),
        format!("  \"sample_tables\": {tables}"),
        format!("  \"moov_error\": {moov_error}"),
    ];
    Ok(format!("{{\n{}\n}}\n", parts.join(",\n")))
}

/// Snapshots every track in a decoded `moov` (accessor errors become snapshot
/// lines, matching the case table).
fn sample_tables_json_for_moov(moov: &MoovBox) -> String {
    let mut items: Vec<String> = Vec::new();
    for (track_index, trak) in moov.trak_boxes.iter().enumerate() {
        let stbl = trak.mdia_box.minf_box.stbl_box.clone();
        let lines = match SampleTableAccessor::new(stbl) {
            Ok(accessor) => sample_table_snapshot(&accessor),
            Err(error) => accessor_error_lines(&error),
        };
        items.push(format!(
            "{{\"track_index\": {track_index}, \"status\": \"ok\", \"snapshot\": {}}}",
            snapshot_json(&lines)
        ));
    }
    format!("[{}]", items.join(", "))
}

/// Fixed whole-`stbl`-box case table shared with the MoonBit differential test
/// (`src/boxes/sample_table_oracle_test.mbt`).
///
/// Success cases (including accessor errors, which embed the frozen
/// `error=accessor` lines) carry the full snapshot; decode failures carry the
/// error kind and reason. Zero-count `stts`/`ctts` runs with distinct deltas
/// are excluded on purpose: upstream's `binary_search` may then return any of
/// the duplicate keys, which issue 0009 does not treat as specified behaviour.
///
/// Changing this table changes the generated MoonBit case file; regenerate it
/// with:
///   (cd tools/oracle && cargo run -- sample-tables-cases --moonbit) \
///     > src/boxes/sample_table_oracle_cases_test.mbt
fn sample_table_cases() -> Vec<(&'static str, Vec<u8>)> {
    fn raw_box(box_type: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let mut out = Vec::with_capacity(8 + payload.len());
        out.extend_from_slice(&((8 + payload.len()) as u32).to_be_bytes());
        out.extend_from_slice(box_type);
        out.extend_from_slice(payload);
        out
    }

    fn full_box(box_type: &[u8; 4], version: u8, flags: u32, body: &[u8]) -> Vec<u8> {
        let mut payload = Vec::with_capacity(4 + body.len());
        payload.push(version);
        payload.extend_from_slice(&(flags & 0x00FF_FFFF).to_be_bytes()[1..]);
        payload.extend_from_slice(body);
        raw_box(box_type, &payload)
    }

    fn count_full_box(box_type: &[u8; 4], version: u8, rows: &[Vec<u8>]) -> Vec<u8> {
        let mut body = ((rows.len() as u32).to_be_bytes()).to_vec();
        for row in rows {
            body.extend_from_slice(row);
        }
        full_box(box_type, version, 0, &body)
    }

    fn u32_row(values: &[u32]) -> Vec<u8> {
        values.iter().flat_map(|v| v.to_be_bytes()).collect()
    }

    fn u64_row(values: &[u64]) -> Vec<u8> {
        values.iter().flat_map(|v| v.to_be_bytes()).collect()
    }

    /// A box whose declared size does not match the bytes that follow it
    /// (used for the "child exceeds its parent payload" decode error).
    fn lying_box(box_type: &[u8; 4], declared_size: u32, body: &[u8]) -> Vec<u8> {
        let mut out = declared_size.to_be_bytes().to_vec();
        out.extend_from_slice(box_type);
        out.extend_from_slice(body);
        out
    }

    fn stsd(entry_types: &[[u8; 4]]) -> Vec<u8> {
        let rows: Vec<Vec<u8>> = entry_types.iter().map(|ty| raw_box(ty, &[])).collect();
        count_full_box(b"stsd", 0, &rows)
    }

    fn stts(entries: &[(u32, u32)]) -> Vec<u8> {
        let rows: Vec<Vec<u8>> = entries
            .iter()
            .map(|(sample_count, sample_delta)| u32_row(&[*sample_count, *sample_delta]))
            .collect();
        count_full_box(b"stts", 0, &rows)
    }

    fn ctts(version: u8, entries: &[(u32, i64)]) -> Vec<u8> {
        let rows: Vec<Vec<u8>> = entries
            .iter()
            .map(|(sample_count, sample_offset)| {
                let mut row = sample_count.to_be_bytes().to_vec();
                if version == 0 {
                    row.extend_from_slice(&(*sample_offset as u32).to_be_bytes());
                } else {
                    row.extend_from_slice(&(*sample_offset as i32).to_be_bytes());
                }
                row
            })
            .collect();
        count_full_box(b"ctts", version, &rows)
    }

    fn cslg(version: u8, values: &[i64; 5]) -> Vec<u8> {
        let mut body = Vec::new();
        for value in values {
            if version == 0 {
                body.extend_from_slice(&(*value as i32).to_be_bytes());
            } else {
                body.extend_from_slice(&value.to_be_bytes());
            }
        }
        full_box(b"cslg", version, 0, &body)
    }

    fn sdtp(version: u8, flags: &[u8]) -> Vec<u8> {
        full_box(b"sdtp", version, 0, flags)
    }

    fn stsc(entries: &[(u32, u32, u32)]) -> Vec<u8> {
        let rows: Vec<Vec<u8>> = entries
            .iter()
            .map(|(first_chunk, sample_per_chunk, sample_description_index)| {
                u32_row(&[*first_chunk, *sample_per_chunk, *sample_description_index])
            })
            .collect();
        count_full_box(b"stsc", 0, &rows)
    }

    fn stsz_fixed(sample_size: u32, sample_count: u32) -> Vec<u8> {
        full_box(b"stsz", 0, 0, &u32_row(&[sample_size, sample_count]))
    }

    fn stsz_variable(entry_sizes: &[u32]) -> Vec<u8> {
        let mut body = u32_row(&[0, entry_sizes.len() as u32]);
        body.extend_from_slice(&u32_row(entry_sizes));
        full_box(b"stsz", 0, 0, &body)
    }

    fn stco(chunk_offsets: &[u32]) -> Vec<u8> {
        let rows: Vec<Vec<u8>> = chunk_offsets.iter().map(|o| u32_row(&[*o])).collect();
        count_full_box(b"stco", 0, &rows)
    }

    fn co64(chunk_offsets: &[u64]) -> Vec<u8> {
        let rows: Vec<Vec<u8>> = chunk_offsets.iter().map(|o| u64_row(&[*o])).collect();
        count_full_box(b"co64", 0, &rows)
    }

    fn stss(sample_numbers: &[u32]) -> Vec<u8> {
        let rows: Vec<Vec<u8>> = sample_numbers.iter().map(|n| u32_row(&[*n])).collect();
        count_full_box(b"stss", 0, &rows)
    }

    fn stbl(children: &[Vec<u8>]) -> Vec<u8> {
        let mut payload = Vec::new();
        for child in children {
            payload.extend_from_slice(child);
        }
        raw_box(b"stbl", &payload)
    }

    let mut cases: Vec<(&'static str, Vec<u8>)> = Vec::new();

    // --- valid sample tables ---
    cases.push((
        "single_sample_fixed",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 100)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(10, 1),
            stco(&[1000]),
        ]),
    ));
    cases.push((
        "multiple_samples_one_chunk",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(3, 25)]),
            stsc(&[(1, 3, 1)]),
            stsz_variable(&[10, 20, 30]),
            stco(&[500]),
        ]),
    ));
    cases.push((
        "several_chunks",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(6, 100)]),
            stsc(&[(1, 2, 1)]),
            stsz_variable(&[10, 20, 30, 40, 50, 60]),
            stco(&[100, 200, 300]),
        ]),
    ));
    cases.push((
        "several_stsc_entries",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(6, 50)]),
            stsc(&[(1, 1, 1), (3, 2, 1)]),
            stsz_variable(&[1, 2, 3, 4, 5, 6]),
            stco(&[10, 20, 30, 40]),
        ]),
    ));
    cases.push((
        "empty_chunk_between",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 10)]),
            stsc(&[(1, 1, 1), (2, 0, 1), (3, 1, 1)]),
            stsz_variable(&[5, 6]),
            stco(&[1, 2, 3]),
        ]),
    ));
    cases.push((
        "empty_trailing_chunk",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 10)]),
            stsc(&[(1, 2, 1), (2, 0, 1)]),
            stsz_fixed(4, 2),
            stco(&[7, 8]),
        ]),
    ));
    cases.push((
        "empty_stsd_no_samples",
        stbl(&[
            stsd(&[]),
            stts(&[]),
            stsc(&[]),
            stsz_variable(&[]),
            stco(&[]),
        ]),
    ));
    cases.push((
        "fixed_stsz_many_samples",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(4, 10)]),
            stsc(&[(1, 4, 1)]),
            stsz_fixed(11, 4),
            stco(&[400]),
        ]),
    ));
    cases.push((
        "large_duration_u32_max",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 4_294_967_295)]),
            stsc(&[(1, 2, 1)]),
            stsz_variable(&[1, 1]),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "timestamp_beyond_u32",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(3, 2_000_000_000)]),
            stsc(&[(1, 3, 1)]),
            stsz_variable(&[1, 1, 1]),
            stco(&[9]),
        ]),
    ));
    cases.push((
        "stss_partial",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(3, 10)]),
            stsc(&[(1, 3, 1)]),
            stsz_fixed(1, 3),
            stco(&[0]),
            stss(&[1, 3]),
        ]),
    ));
    cases.push((
        "stss_missing_all_sync",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 10)]),
            stsc(&[(1, 2, 1)]),
            stsz_fixed(1, 2),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "stss_empty_none_sync",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 10)]),
            stsc(&[(1, 2, 1)]),
            stsz_fixed(1, 2),
            stco(&[0]),
            stss(&[]),
        ]),
    ));
    cases.push((
        "ctts_v0_zero_offsets",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(3, 10)]),
            ctts(0, &[(3, 0)]),
            stsc(&[(1, 3, 1)]),
            stsz_fixed(1, 3),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "ctts_v1_negative_and_large",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(3, 10)]),
            ctts(1, &[(1, -100), (2, 2_147_483_647)]),
            stsc(&[(1, 3, 1)]),
            stsz_fixed(1, 3),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "ctts_v0_u32_max",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 10)]),
            ctts(0, &[(1, 10), (1, 4_294_967_295)]),
            stsc(&[(1, 2, 1)]),
            stsz_fixed(1, 2),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "cslg_v0",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            cslg(0, &[100, -50, 200, 0, 1000]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "cslg_v1",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            cslg(
                1,
                &[4_294_967_296, -2_147_483_648, 5_000_000_000, -1, 9_000_000_000],
            ),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "sdtp_present",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 10)]),
            stsc(&[(1, 2, 1)]),
            stsz_fixed(1, 2),
            stco(&[0]),
            sdtp(0, &[0x80, 0xFF]),
        ]),
    ));
    cases.push((
        "co64_beyond_u32",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 10)]),
            stsc(&[(1, 1, 1)]),
            stsz_variable(&[5, 6]),
            co64(&[4_294_967_296, 1_099_511_627_776]),
        ]),
    ));
    cases.push((
        "stco_u32_max",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 1)]),
            stsc(&[(1, 1, 1)]),
            stsz_variable(&[1]),
            stco(&[4_294_967_295]),
        ]),
    ));
    cases.push((
        "unknown_child",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(3, 1),
            stco(&[0]),
            raw_box(b"zzzz", &[0xAA, 0xBB]),
        ]),
    ));
    cases.push((
        "duplicate_stsz_first_wins",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 7)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(3, 1),
            stsz_fixed(99, 1),
            stco(&[50]),
        ]),
    ));
    cases.push((
        "stco_and_co64_prefers_stco",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[100]),
            co64(&[200]),
        ]),
    ));

    // --- accessor errors (decoded successfully, then rejected by the accessor) ---
    cases.push((
        "error_stts_stsz_mismatch",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 100)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(10, 2),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "error_stts_ctts_mismatch",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 100)]),
            ctts(0, &[(1, 0)]),
            stsc(&[(1, 2, 1)]),
            stsz_fixed(10, 2),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "error_stts_stsc_mismatch",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 100)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(10, 2),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "error_chunks_without_stsc",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 100)]),
            stsc(&[]),
            stsz_fixed(10, 1),
            stco(&[100]),
        ]),
    ));
    cases.push((
        "error_first_chunk_not_one",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 100)]),
            stsc(&[(2, 1, 1)]),
            stsz_fixed(10, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "error_missing_sample_entry",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 100)]),
            stsc(&[(1, 1, 2)]),
            stsz_fixed(10, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "error_missing_sample_entry_empty_stsd",
        stbl(&[
            stsd(&[]),
            stts(&[(1, 100)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(10, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "error_stsc_not_monotonic",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 100)]),
            stsc(&[(1, 1, 1), (1, 1, 1)]),
            stsz_fixed(10, 2),
            stco(&[0, 1]),
        ]),
    ));
    cases.push((
        "error_last_chunk_too_large",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 100)]),
            stsc(&[(1, 1, 1), (3, 1, 1)]),
            stsz_fixed(10, 2),
            stco(&[0, 1]),
        ]),
    ));
    cases.push((
        "error_fixed_offset_overflow",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 100)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(10, 1),
            co64(&[u64::MAX - 5]),
        ]),
    ));
    cases.push((
        "error_variable_offset_overflow",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 100)]),
            stsc(&[(1, 2, 1)]),
            stsz_variable(&[1, 1]),
            co64(&[u64::MAX - 1]),
        ]),
    ));
    cases.push((
        "error_stts_count_overflow",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(4_294_967_295, 1), (1, 1)]),
            stsc(&[]),
            stsz_variable(&[]),
            stco(&[]),
        ]),
    ));
    cases.push((
        "error_ctts_count_overflow",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 1)]),
            ctts(0, &[(4_294_967_295, 0), (1, 0)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));

    // --- decode errors ---
    cases.push((
        "decode_missing_stsd",
        stbl(&[
            stts(&[(1, 10)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_missing_stts",
        stbl(&[
            stsd(&[*b"test"]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_missing_stsc",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_missing_stsz",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            stsc(&[(1, 1, 1)]),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_missing_stco_or_co64",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
        ]),
    ));
    cases.push((
        "decode_ctts_version",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            full_box(b"ctts", 2, 0, &u32_row(&[0])),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_cslg_version",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            full_box(b"cslg", 2, 0, &[]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_sdtp_version",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            sdtp(1, &[0]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_stss_zero_number",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
            stss(&[0]),
        ]),
    ));
    cases.push((
        "decode_stsc_zero_first_chunk",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            stsc(&[(0, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_stsc_zero_description_index",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            stsc(&[(1, 1, 0)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_stts_entry_truncated",
        stbl(&[
            stsd(&[*b"test"]),
            full_box(b"stts", 0, 0, &u32_row(&[1])),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_stsz_variable_truncated",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(2, 10)]),
            stsc(&[(1, 2, 1)]),
            full_box(b"stsz", 0, 0, &u32_row(&[0, 2, 5])),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_stsd_entry_truncated",
        stbl(&[
            full_box(b"stsd", 0, 0, &[0, 0, 0, 1, 0, 0, 0, 8]),
            stts(&[(1, 10)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            stco(&[0]),
        ]),
    ));
    cases.push((
        "decode_child_declared_size_exceeds_payload",
        stbl(&[
            stsd(&[*b"test"]),
            stts(&[(1, 10)]),
            stsc(&[(1, 1, 1)]),
            stsz_fixed(1, 1),
            lying_box(b"stco", 100, &u32_row(&[0, 0])),
        ]),
    ));

    cases
}

/// Runs the fixed `stbl` case table and emits the normalised JSON.
fn run_sample_table_cases() -> String {
    let cases = sample_table_cases();
    let mut items: Vec<String> = Vec::new();
    for (name, input) in &cases {
        let mut entry = format!("{{\"name\": \"{name}\", \"input\": \"{}\"", hex(input));
        match sample_table_outcome(input) {
            SampleTableOutcome::Ok(snapshot) => {
                let _ = write!(
                    entry,
                    ", \"ok\": true, \"snapshot\": {}",
                    snapshot_json(&snapshot)
                );
            }
            SampleTableOutcome::DecodeErr { kind, reason } => {
                let _ = write!(
                    entry,
                    ", \"ok\": false, \"error_kind\": \"{kind}\", \"reason\": {}",
                    json_string_to(&reason)
                );
            }
        }
        entry.push('}');
        items.push(entry);
    }
    format!(
        "{{\"schema\": {SCHEMA_VERSION}, \"upstream_sha\": \"{UPSTREAM_SHA}\", \"cases\": [{}]}}",
        items.join(", ")
    )
}

/// Emits the MoonBit case-table file consumed by
/// `src/boxes/sample_table_oracle_test.mbt`.
fn sample_table_moonbit_cases() -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- sample-tables-cases --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (sample_table_cases)."
    );
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(
        out,
        "// DO NOT EDIT MANUALLY. Regenerate (canonical formatting is part of the file):"
    );
    let _ = writeln!(
        out,
        "//   (cd tools/oracle && cargo run -- sample-tables-cases --moonbit) \\"
    );
    let _ = writeln!(
        out,
        "//     > src/boxes/sample_table_oracle_cases_test.mbt"
    );
    let _ = writeln!(out, "//   moon fmt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `sample-tables-cases` が返すケース表（生成物）。"
    );
    let _ = writeln!(out, "///");
    let _ = writeln!(
        out,
        "/// 型は `src/boxes/sample_table_oracle_test.mbt` で定義する。手で編集しない。"
    );
    let _ = writeln!(
        out,
        "let oracle_sample_table_cases : Array[OracleSampleTableCase] = ["
    );
    for (name, input) in &sample_table_cases() {
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: \"{name}\",");
        let _ = writeln!(out, "    input: {},", moonbit_bytes(input));
        match sample_table_outcome(input) {
            SampleTableOutcome::Ok(snapshot) => {
                let _ = writeln!(out, "    ok: true,");
                write_moonbit_snapshot(&mut out, &snapshot, 4);
                let _ = writeln!(out, "    error_kind: \"\",");
                let _ = writeln!(out, "    reason: \"\",");
            }
            SampleTableOutcome::DecodeErr { kind, reason } => {
                let _ = writeln!(out, "    ok: false,");
                let _ = writeln!(out, "    snapshot: [],");
                let _ = writeln!(out, "    error_kind: \"{kind}\",");
                let _ = writeln!(out, "    reason: {},", moonbit_string(&reason));
            }
        }
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}

/// Fixtures embedded (with `include_bytes!`) in the generated MoonBit
/// differential test. The generated data embeds each track's `stbl` box
/// re-encoded by upstream, so it changes exactly when a fixture's sample
/// tables change.
const SAMPLE_TABLE_FIXTURES: &[(&str, &[u8])] = &[
    (
        "black-h264-video.mp4",
        include_bytes!("../../../tests/fixtures/upstream/black-h264-video.mp4"),
    ),
    (
        "black-h265-video.mp4",
        include_bytes!("../../../tests/fixtures/upstream/black-h265-video.mp4"),
    ),
    (
        "black-h265-hvc1-video.mp4",
        include_bytes!("../../../tests/fixtures/upstream/black-h265-hvc1-video.mp4"),
    ),
    (
        "black-av1-video.mp4",
        include_bytes!("../../../tests/fixtures/upstream/black-av1-video.mp4"),
    ),
    (
        "black-vp9-video.mp4",
        include_bytes!("../../../tests/fixtures/upstream/black-vp9-video.mp4"),
    ),
    (
        "beep-aac-audio.mp4",
        include_bytes!("../../../tests/fixtures/upstream/beep-aac-audio.mp4"),
    ),
    (
        "beep-opus-audio.mp4",
        include_bytes!("../../../tests/fixtures/upstream/beep-opus-audio.mp4"),
    ),
    (
        "beep-flac-audio.mp4",
        include_bytes!("../../../tests/fixtures/upstream/beep-flac-audio.mp4"),
    ),
    (
        "black-h264-fmp4.mp4",
        include_bytes!("../../../tests/fixtures/upstream/black-h264-fmp4.mp4"),
    ),
];

/// Extracts every track's `stbl` from every fixture and re-encodes it with
/// upstream (panics on failure: generation must not silently emit stale data).
fn sample_table_fixture_stbls() -> Vec<(&'static str, usize, Vec<u8>)> {
    let mut out = Vec::new();
    for (name, data) in SAMPLE_TABLE_FIXTURES {
        let moov_bytes =
            extract_top_level_box(data, b"moov").unwrap_or_else(|(kind, reason)| {
                panic!("{name}: top-level moov extraction failed: {kind}: {reason}")
            });
        let (moov, _) = MoovBox::decode(&moov_bytes).unwrap_or_else(|e| {
            panic!(
                "{name}: moov decode failed: {}: {}",
                error_kind_str(e.kind),
                e.reason
            )
        });
        for (track_index, trak) in moov.trak_boxes.iter().enumerate() {
            let stbl = trak
                .mdia_box
                .minf_box
                .stbl_box
                .encode_to_vec()
                .unwrap_or_else(|e| {
                    panic!(
                        "{name} track {track_index}: stbl encode failed: {}: {}",
                        error_kind_str(e.kind),
                        e.reason
                    )
                });
            out.push((*name, track_index, stbl));
        }
    }
    out
}

/// Emits the fixture differential data consumed by
/// `src/boxes/sample_table_oracle_test.mbt`.
fn sample_table_moonbit_fixtures() -> String {
    let fixtures = sample_table_fixture_stbls();
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- sample-tables-fixtures --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (SAMPLE_TABLE_FIXTURES)."
    );
    let _ = writeln!(
        out,
        "// Fixtures (per-track `stbl` re-encoded by upstream from the checked-in mp4):"
    );
    for (name, track_index, stbl) in &fixtures {
        let _ = writeln!(
            out,
            "//   {name} track {track_index}: stbl {} bytes, sha256 {}",
            stbl.len(),
            sha256_hex(stbl)
        );
    }
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(
        out,
        "// DO NOT EDIT MANUALLY. Regenerate (canonical formatting is part of the file):"
    );
    let _ = writeln!(
        out,
        "//   (cd tools/oracle && cargo run -- sample-tables-fixtures --moonbit) \\"
    );
    let _ = writeln!(
        out,
        "//     > src/boxes/sample_table_oracle_fixtures_test.mbt"
    );
    let _ = writeln!(out, "//   moon fmt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `sample-tables-fixtures` が返す fixture 走査（生成物）。"
    );
    let _ = writeln!(out, "///");
    let _ = writeln!(
        out,
        "/// 型は `src/boxes/sample_table_oracle_test.mbt` で定義する。手で編集しない。"
    );
    let _ = writeln!(
        out,
        "let oracle_sample_table_fixtures : Array[OracleSampleTableFixture] = ["
    );
    for (name, track_index, stbl) in &fixtures {
        let snapshot = match sample_table_outcome(stbl) {
            SampleTableOutcome::Ok(snapshot) => snapshot,
            SampleTableOutcome::DecodeErr { kind, reason } => {
                panic!("{name} track {track_index}: re-decoded stbl failed: {kind}: {reason}")
            }
        };
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: \"{name}\",");
        let _ = writeln!(out, "    track_index: {track_index},");
        let _ = writeln!(out, "    stbl: {},", moonbit_bytes(stbl));
        write_moonbit_snapshot(&mut out, &snapshot, 4);
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}

// === sample entries (issue 0010) ===

/// Renders `Option` numeric fields in the `key=value|none` snapshot form.
fn opt_num_str<T: std::fmt::Display>(name: &str, value: Option<T>) -> String {
    match value {
        Some(v) => format!("{name}={v}"),
        None => format!("{name}=none"),
    }
}

fn fixed_16_16_str(value: &FixedPointNumber<u16, u16>) -> String {
    format!("{:04x}{:04x}", value.integer, value.fraction)
}

fn visual_sample_entry_lines(
    lines: &mut Vec<String>,
    prefix: &str,
    v: &VisualSampleEntryFields,
) {
    lines.push(format!(
        "{prefix}.data_reference_index={}",
        v.data_reference_index.get()
    ));
    lines.push(format!("{prefix}.width={}", v.width));
    lines.push(format!("{prefix}.height={}", v.height));
    lines.push(format!(
        "{prefix}.horizresolution={}",
        fixed_16_16_str(&v.horizresolution)
    ));
    lines.push(format!(
        "{prefix}.vertresolution={}",
        fixed_16_16_str(&v.vertresolution)
    ));
    lines.push(format!("{prefix}.frame_count={}", v.frame_count));
    lines.push(format!("{prefix}.compressorname={}", hex(&v.compressorname)));
    lines.push(format!("{prefix}.depth={:04x}", v.depth));
}

fn audio_sample_entry_lines(
    lines: &mut Vec<String>,
    prefix: &str,
    a: &AudioSampleEntryFields,
) {
    lines.push(format!(
        "{prefix}.data_reference_index={}",
        a.data_reference_index.get()
    ));
    lines.push(format!("{prefix}.channelcount={}", a.channelcount));
    lines.push(format!("{prefix}.samplesize={}", a.samplesize));
    lines.push(format!(
        "{prefix}.samplerate={}",
        fixed_16_16_str(&a.samplerate)
    ));
}

fn byte_list_lines(lines: &mut Vec<String>, name: &str, items: &[Vec<u8>]) {
    lines.push(format!("{name}.count={}", items.len()));
    for (i, item) in items.iter().enumerate() {
        lines.push(format!("{name}[{i}].size={}", item.len()));
        lines.push(format!("{name}[{i}].hex={}", hex(item)));
    }
}

fn unknown_box_lines(lines: &mut Vec<String>, boxes: &[shiguredo_mp4::boxes::UnknownBox]) {
    lines.push(format!("unknown_boxes.count={}", boxes.len()));
    for (i, b) in boxes.iter().enumerate() {
        lines.push(format!("unknown_box[{i}].type={}", b.box_type));
        lines.push(format!("unknown_box[{i}].payload.size={}", b.payload.len()));
        lines.push(format!("unknown_box[{i}].payload.hex={}", hex(&b.payload)));
    }
}

fn avcc_lines(lines: &mut Vec<String>, prefix: &str, b: &shiguredo_mp4::boxes::AvccBox) {
    lines.push(format!(
        "{prefix}.avc_profile_indication={}",
        b.avc_profile_indication
    ));
    lines.push(format!(
        "{prefix}.profile_compatibility={}",
        b.profile_compatibility
    ));
    lines.push(format!(
        "{prefix}.avc_level_indication={}",
        b.avc_level_indication
    ));
    lines.push(format!(
        "{prefix}.length_size_minus_one={}",
        b.length_size_minus_one.get()
    ));
    byte_list_lines(lines, &format!("{prefix}.sps"), &b.sps_list);
    byte_list_lines(lines, &format!("{prefix}.pps"), &b.pps_list);
    lines.push(opt_num_str(
        &format!("{prefix}.chroma_format"),
        b.chroma_format.map(|u| u.get()),
    ));
    lines.push(opt_num_str(
        &format!("{prefix}.bit_depth_luma_minus8"),
        b.bit_depth_luma_minus8.map(|u| u.get()),
    ));
    lines.push(opt_num_str(
        &format!("{prefix}.bit_depth_chroma_minus8"),
        b.bit_depth_chroma_minus8.map(|u| u.get()),
    ));
    byte_list_lines(lines, &format!("{prefix}.sps_ext"), &b.sps_ext_list);
}

fn hvcc_lines(lines: &mut Vec<String>, prefix: &str, b: &shiguredo_mp4::boxes::HvccBox) {
    lines.push(format!(
        "{prefix}.general_profile_space={}",
        b.general_profile_space.get()
    ));
    lines.push(format!(
        "{prefix}.general_tier_flag={}",
        b.general_tier_flag.get()
    ));
    lines.push(format!(
        "{prefix}.general_profile_idc={}",
        b.general_profile_idc.get()
    ));
    lines.push(format!(
        "{prefix}.general_profile_compatibility_flags={:08x}",
        b.general_profile_compatibility_flags
    ));
    lines.push(format!(
        "{prefix}.general_constraint_indicator_flags={:012x}",
        b.general_constraint_indicator_flags.get()
    ));
    lines.push(format!("{prefix}.general_level_idc={}", b.general_level_idc));
    lines.push(format!(
        "{prefix}.min_spatial_segmentation_idc={}",
        b.min_spatial_segmentation_idc.get()
    ));
    lines.push(format!(
        "{prefix}.parallelism_type={}",
        b.parallelism_type.get()
    ));
    lines.push(format!(
        "{prefix}.chroma_format_idc={}",
        b.chroma_format_idc.get()
    ));
    lines.push(format!(
        "{prefix}.bit_depth_luma_minus8={}",
        b.bit_depth_luma_minus8.get()
    ));
    lines.push(format!(
        "{prefix}.bit_depth_chroma_minus8={}",
        b.bit_depth_chroma_minus8.get()
    ));
    lines.push(format!("{prefix}.avg_frame_rate={}", b.avg_frame_rate));
    lines.push(format!(
        "{prefix}.constant_frame_rate={}",
        b.constant_frame_rate.get()
    ));
    lines.push(format!(
        "{prefix}.num_temporal_layers={}",
        b.num_temporal_layers.get()
    ));
    lines.push(format!(
        "{prefix}.temporal_id_nested={}",
        b.temporal_id_nested.get()
    ));
    lines.push(format!(
        "{prefix}.length_size_minus_one={}",
        b.length_size_minus_one.get()
    ));
    lines.push(format!("{prefix}.nalu_arrays.count={}", b.nalu_arrays.len()));
    for (i, array) in b.nalu_arrays.iter().enumerate() {
        lines.push(format!(
            "{prefix}.nalu_arrays[{i}].array_completeness={}",
            array.array_completeness.get()
        ));
        lines.push(format!(
            "{prefix}.nalu_arrays[{i}].nal_unit_type={}",
            array.nal_unit_type.get()
        ));
        byte_list_lines(
            lines,
            &format!("{prefix}.nalu_arrays[{i}].nalus"),
            &array.nalus,
        );
    }
}

fn vpcc_lines(lines: &mut Vec<String>, prefix: &str, b: &shiguredo_mp4::boxes::VpccBox) {
    lines.push(format!("{prefix}.profile={}", b.profile));
    lines.push(format!("{prefix}.level={}", b.level));
    lines.push(format!("{prefix}.bit_depth={}", b.bit_depth.get()));
    lines.push(format!(
        "{prefix}.chroma_subsampling={}",
        b.chroma_subsampling.get()
    ));
    lines.push(format!(
        "{prefix}.video_full_range_flag={}",
        b.video_full_range_flag.get()
    ));
    lines.push(format!("{prefix}.colour_primaries={}", b.colour_primaries));
    lines.push(format!(
        "{prefix}.transfer_characteristics={}",
        b.transfer_characteristics
    ));
    lines.push(format!(
        "{prefix}.matrix_coefficients={}",
        b.matrix_coefficients
    ));
    lines.push(format!(
        "{prefix}.codec_initialization_data.size={}",
        b.codec_initialization_data.len()
    ));
    lines.push(format!(
        "{prefix}.codec_initialization_data.hex={}",
        hex(&b.codec_initialization_data)
    ));
}

fn av1c_lines(lines: &mut Vec<String>, prefix: &str, b: &shiguredo_mp4::boxes::Av1cBox) {
    lines.push(format!("{prefix}.seq_profile={}", b.seq_profile.get()));
    lines.push(format!("{prefix}.seq_level_idx_0={}", b.seq_level_idx_0.get()));
    lines.push(format!("{prefix}.seq_tier_0={}", b.seq_tier_0.get()));
    lines.push(format!("{prefix}.high_bitdepth={}", b.high_bitdepth.get()));
    lines.push(format!("{prefix}.twelve_bit={}", b.twelve_bit.get()));
    lines.push(format!("{prefix}.monochrome={}", b.monochrome.get()));
    lines.push(format!(
        "{prefix}.chroma_subsampling_x={}",
        b.chroma_subsampling_x.get()
    ));
    lines.push(format!(
        "{prefix}.chroma_subsampling_y={}",
        b.chroma_subsampling_y.get()
    ));
    lines.push(format!(
        "{prefix}.chroma_sample_position={}",
        b.chroma_sample_position.get()
    ));
    lines.push(opt_num_str(
        &format!("{prefix}.initial_presentation_delay_minus_one"),
        b.initial_presentation_delay_minus_one.map(|u| u.get()),
    ));
    lines.push(format!("{prefix}.config_obus.size={}", b.config_obus.len()));
    lines.push(format!("{prefix}.config_obus.hex={}", hex(&b.config_obus)));
}

fn dops_lines(lines: &mut Vec<String>, prefix: &str, b: &shiguredo_mp4::boxes::DopsBox) {
    lines.push(format!(
        "{prefix}.output_channel_count={}",
        b.output_channel_count
    ));
    lines.push(format!("{prefix}.pre_skip={}", b.pre_skip));
    lines.push(format!("{prefix}.input_sample_rate={}", b.input_sample_rate));
    lines.push(format!("{prefix}.output_gain={}", b.output_gain));
}

fn esds_lines(lines: &mut Vec<String>, prefix: &str, b: &shiguredo_mp4::boxes::EsdsBox) {
    let es = &b.es;
    lines.push(format!("{prefix}.es_id={}", es.es_id));
    lines.push(format!(
        "{prefix}.stream_priority={}",
        es.stream_priority.get()
    ));
    lines.push(opt_num_str(
        &format!("{prefix}.depends_on_es_id"),
        es.depends_on_es_id,
    ));
    lines.push(format!(
        "{prefix}.url_string={}",
        match &es.url_string {
            Some(url) => json_string_to(url),
            None => "none".to_string(),
        }
    ));
    lines.push(opt_num_str(&format!("{prefix}.ocr_es_id"), es.ocr_es_id));
    let d = &es.dec_config_descr;
    lines.push(format!(
        "{prefix}.dec_config.object_type_indication={:02x}",
        d.object_type_indication
    ));
    lines.push(format!(
        "{prefix}.dec_config.stream_type={}",
        d.stream_type.get()
    ));
    lines.push(format!("{prefix}.dec_config.up_stream={}", d.up_stream.get()));
    lines.push(format!(
        "{prefix}.dec_config.buffer_size_db={}",
        d.buffer_size_db.get()
    ));
    lines.push(format!("{prefix}.dec_config.max_bitrate={}", d.max_bitrate));
    lines.push(format!("{prefix}.dec_config.avg_bitrate={}", d.avg_bitrate));
    match &d.dec_specific_info {
        Some(info) => {
            lines.push(format!(
                "{prefix}.dec_specific_info.size={}",
                info.payload.len()
            ));
            lines.push(format!(
                "{prefix}.dec_specific_info.hex={}",
                hex(&info.payload)
            ));
        }
        None => lines.push(format!("{prefix}.dec_specific_info=none")),
    }
}

fn dfla_lines(lines: &mut Vec<String>, prefix: &str, b: &shiguredo_mp4::boxes::DflaBox) {
    lines.push(format!(
        "{prefix}.metadata_blocks.count={}",
        b.metadata_blocks.len()
    ));
    for (i, block) in b.metadata_blocks.iter().enumerate() {
        lines.push(format!(
            "{prefix}.metadata_blocks[{i}].last_metadata_block_flag={}",
            block.last_metadata_block_flag.get()
        ));
        lines.push(format!(
            "{prefix}.metadata_blocks[{i}].block_type={}",
            block.block_type.get()
        ));
        lines.push(format!(
            "{prefix}.metadata_blocks[{i}].block_data.size={}",
            block.block_data.len()
        ));
        lines.push(format!(
            "{prefix}.metadata_blocks[{i}].block_data.hex={}",
            hex(&block.block_data)
        ));
    }
}

/// Frozen per-entry snapshot shared by the JSON modes and the generated
/// MoonBit case/fixture files.
fn sample_entry_snapshot(entry: &SampleEntry) -> Vec<String> {
    let mut lines = Vec::new();
    let variant = match entry {
        SampleEntry::Avc1(_) => "avc1",
        SampleEntry::Hev1(_) => "hev1",
        SampleEntry::Hvc1(_) => "hvc1",
        SampleEntry::Vp08(_) => "vp08",
        SampleEntry::Vp09(_) => "vp09",
        SampleEntry::Av01(_) => "av01",
        SampleEntry::Opus(_) => "Opus",
        SampleEntry::Mp4a(_) => "mp4a",
        SampleEntry::Flac(_) => "fLaC",
        SampleEntry::Stpp(_) => "stpp",
        SampleEntry::Wvtt(_) => "wvtt",
        SampleEntry::Tx3g(_) => "tx3g",
        SampleEntry::Unknown(_) => "unknown",
    };
    lines.push(format!("variant={variant}"));
    lines.push(format!("box_type={}", entry.box_type()));
    lines.push(format!("is_unknown={}", bool_str(entry.is_unknown_box())));
    lines.push(opt_num_str(
        "audio_channel_count",
        entry.audio_channel_count(),
    ));
    lines.push(opt_num_str("audio_sample_rate", entry.audio_sample_rate()));
    lines.push(opt_num_str("audio_sample_size", entry.audio_sample_size()));
    lines.push(format!(
        "video_resolution={}",
        match entry.video_resolution() {
            Some((w, h)) => format!("{w}x{h}"),
            None => "none".to_string(),
        }
    ));
    match entry {
        SampleEntry::Avc1(b) => {
            visual_sample_entry_lines(&mut lines, "visual", &b.visual);
            avcc_lines(&mut lines, "avcC", &b.avcc_box);
            unknown_box_lines(&mut lines, &b.unknown_boxes);
        }
        SampleEntry::Hev1(b) => {
            visual_sample_entry_lines(&mut lines, "visual", &b.visual);
            hvcc_lines(&mut lines, "hvcC", &b.hvcc_box);
            unknown_box_lines(&mut lines, &b.unknown_boxes);
        }
        SampleEntry::Hvc1(b) => {
            visual_sample_entry_lines(&mut lines, "visual", &b.visual);
            hvcc_lines(&mut lines, "hvcC", &b.hvcc_box);
            unknown_box_lines(&mut lines, &b.unknown_boxes);
        }
        SampleEntry::Vp08(b) => {
            visual_sample_entry_lines(&mut lines, "visual", &b.visual);
            vpcc_lines(&mut lines, "vpcC", &b.vpcc_box);
            unknown_box_lines(&mut lines, &b.unknown_boxes);
        }
        SampleEntry::Vp09(b) => {
            visual_sample_entry_lines(&mut lines, "visual", &b.visual);
            vpcc_lines(&mut lines, "vpcC", &b.vpcc_box);
            unknown_box_lines(&mut lines, &b.unknown_boxes);
        }
        SampleEntry::Av01(b) => {
            visual_sample_entry_lines(&mut lines, "visual", &b.visual);
            av1c_lines(&mut lines, "av1C", &b.av1c_box);
            unknown_box_lines(&mut lines, &b.unknown_boxes);
        }
        SampleEntry::Opus(b) => {
            audio_sample_entry_lines(&mut lines, "audio", &b.audio);
            dops_lines(&mut lines, "dOps", &b.dops_box);
            unknown_box_lines(&mut lines, &b.unknown_boxes);
        }
        SampleEntry::Mp4a(b) => {
            audio_sample_entry_lines(&mut lines, "audio", &b.audio);
            esds_lines(&mut lines, "esds", &b.esds_box);
            unknown_box_lines(&mut lines, &b.unknown_boxes);
        }
        SampleEntry::Flac(b) => {
            audio_sample_entry_lines(&mut lines, "audio", &b.audio);
            dfla_lines(&mut lines, "dfLa", &b.dfla_box);
            unknown_box_lines(&mut lines, &b.unknown_boxes);
        }
        SampleEntry::Unknown(b) => {
            lines.push(format!(
                "unknown.size_kind={}",
                match b.box_size {
                    BoxSize::U32(_) => "u32",
                    BoxSize::U64(_) => "u64",
                }
            ));
            lines.push(format!("unknown.payload.size={}", b.payload.len()));
            lines.push(format!("unknown.payload.hex={}", hex(&b.payload)));
        }
        _ => {}
    }
    let children: Vec<String> = entry
        .children()
        .map(|c| format!("{}", c.box_type()))
        .collect();
    lines.push(format!("children.count={}", children.len()));
    for (i, ty) in children.iter().enumerate() {
        lines.push(format!("children[{i}].type={ty}"));
    }
    lines
}

/// One decoded sample-entry observation: the frozen snapshot plus either the
/// re-encoded bytes or the encode/decode error.
enum SampleEntryOutcome {
    Ok { snapshot: Vec<String>, encoded: Vec<u8> },
    EncodeErr {
        snapshot: Vec<String>,
        kind: &'static str,
        reason: String,
    },
    DecodeErr { kind: &'static str, reason: String },
}

fn sample_entry_outcome(input: &[u8]) -> SampleEntryOutcome {
    match SampleEntry::decode(input) {
        Err(error) => SampleEntryOutcome::DecodeErr {
            kind: error_kind_str(error.kind),
            reason: error.reason,
        },
        Ok((entry, _)) => {
            let snapshot = sample_entry_snapshot(&entry);
            match entry.encode_to_vec() {
                Ok(encoded) => SampleEntryOutcome::Ok { snapshot, encoded },
                Err(error) => SampleEntryOutcome::EncodeErr {
                    snapshot,
                    kind: error_kind_str(error.kind),
                    reason: error.reason,
                },
            }
        }
    }
}

/// Fixed bare-sample-entry case table shared with the MoonBit differential
/// test (`src/boxes/sample_entry_oracle_test.mbt`).
///
/// Changing this table changes the generated MoonBit case file; regenerate it
/// with:
///   (cd tools/oracle && cargo run -- sample-entries-cases --moonbit) \
///     > src/boxes/sample_entry_oracle_cases_test.mbt
fn sample_entry_cases() -> Vec<(&'static str, Vec<u8>)> {
    fn raw_box(box_type: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let mut out = Vec::with_capacity(8 + payload.len());
        out.extend_from_slice(&((8 + payload.len()) as u32).to_be_bytes());
        out.extend_from_slice(box_type);
        out.extend_from_slice(payload);
        out
    }

    fn full_box(box_type: &[u8; 4], version: u8, flags: u32, body: &[u8]) -> Vec<u8> {
        let mut payload = Vec::with_capacity(4 + body.len());
        payload.push(version);
        payload.extend_from_slice(&(flags & 0x00FF_FFFF).to_be_bytes()[1..]);
        payload.extend_from_slice(body);
        raw_box(box_type, &payload)
    }

    fn entry(box_type: &[u8; 4], fields: &[u8], children: &[Vec<u8>]) -> Vec<u8> {
        let mut payload = fields.to_vec();
        for child in children {
            payload.extend_from_slice(child);
        }
        raw_box(box_type, &payload)
    }

    /// 78-byte ISO visual sample entry fields.
    fn visual_fields(dref: u16, width: u16, height: u16) -> Vec<u8> {
        let mut v = Vec::with_capacity(78);
        v.extend_from_slice(&[0; 6]);
        v.extend_from_slice(&dref.to_be_bytes());
        v.extend_from_slice(&[0; 16]);
        v.extend_from_slice(&width.to_be_bytes());
        v.extend_from_slice(&height.to_be_bytes());
        v.extend_from_slice(&0x0048_0000u32.to_be_bytes());
        v.extend_from_slice(&0x0048_0000u32.to_be_bytes());
        v.extend_from_slice(&[0; 4]);
        v.extend_from_slice(&1u16.to_be_bytes());
        v.extend_from_slice(&[0; 32]);
        v.extend_from_slice(&0x0018u16.to_be_bytes());
        v.extend_from_slice(&0xFFFFu16.to_be_bytes());
        v
    }

    /// 28-byte ISO audio sample entry fields (`samplerate` as u16.u16).
    fn audio_fields(dref: u16, channels: u16, sample_size: u16, rate: u32) -> Vec<u8> {
        let mut v = Vec::with_capacity(28);
        v.extend_from_slice(&[0; 6]);
        v.extend_from_slice(&dref.to_be_bytes());
        v.extend_from_slice(&[0; 8]);
        v.extend_from_slice(&channels.to_be_bytes());
        v.extend_from_slice(&sample_size.to_be_bytes());
        v.extend_from_slice(&[0; 4]);
        v.extend_from_slice(&rate.to_be_bytes());
        v
    }

    fn avcc(profile: u8, with_tail: bool) -> Vec<u8> {
        let sps: &[u8] = &[0x67, 0x64, 0x00, 0x1e, 0xac, 0xd9, 0x40, 0xa0, 0x2f];
        let pps: &[u8] = &[0x68, 0xee, 0x06, 0xe2];
        let mut body = vec![1, profile, 0x00, 0x1e, 0xff, 0xe1];
        body.extend_from_slice(&(sps.len() as u16).to_be_bytes());
        body.extend_from_slice(sps);
        body.push(1);
        body.extend_from_slice(&(pps.len() as u16).to_be_bytes());
        body.extend_from_slice(pps);
        if with_tail {
            body.extend_from_slice(&[0xfd, 0xf8, 0xf8, 0x00]);
        }
        raw_box(b"avcC", &body)
    }

    /// Minimal valid `hvcC` (empty NALU array list).
    fn hvcc() -> Vec<u8> {
        raw_box(
            b"hvcC",
            &[
                0x01, 0x01, 0x60, 0x00, 0x00, 0x00, 0x90, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78,
                0xf0, 0x00, 0xfc, 0xfc, 0xf8, 0xf8, 0x00, 0x00, 0x03, 0x00,
            ],
        )
    }

    /// `hvcC` v1 with caller-chosen PTL bytes (space+tier+idc, compat,
    /// 6-byte constraint, level); the shared trailing fields stay constant.
    fn hvcc_with(ptl: u8, compat: u32, constraint: &[u8; 6], level: u8) -> Vec<u8> {
        let mut payload = vec![0x01, ptl];
        payload.extend_from_slice(&compat.to_be_bytes());
        payload.extend_from_slice(constraint);
        payload.push(level);
        payload.extend_from_slice(&[0xf0, 0x00, 0xfc, 0xfc, 0xf8, 0xf8, 0x00, 0x00, 0x03, 0x00]);
        raw_box(b"hvcC", &payload)
    }

    fn vpcc() -> Vec<u8> {
        full_box(b"vpcC", 1, 0, &[0, 10, 0x80, 1, 1, 1, 0, 0])
    }

    /// `vpcC` v1 with caller-chosen profile / level / bit_depth.
    fn vpcc_with(profile: u8, level: u8, bit_depth: u8) -> Vec<u8> {
        full_box(
            b"vpcC",
            1,
            0,
            &[profile, level, bit_depth << 4, 1, 1, 1, 0, 0],
        )
    }

    fn av1c() -> Vec<u8> {
        raw_box(b"av1C", &[0x81, 0x00, 0x00, 0x00])
    }

    /// `av1C` v1 with caller-chosen seq_profile / level / tier / depth flags.
    fn av1c_with(profile: u8, level: u8, tier: u8, high: u8, twelve: u8) -> Vec<u8> {
        raw_box(
            b"av1C",
            &[
                0x81,
                (profile << 5) | level,
                (tier << 7) | (high << 6) | (twelve << 5),
                0x00,
            ],
        )
    }

    fn dops() -> Vec<u8> {
        raw_box(b"dOps", &[0, 2, 0x01, 0x38, 0, 0, 0xbb, 0x80, 0, 0, 0])
    }

    /// `esds` v0 with a minimal AAC ES descriptor chain.
    ///
    /// `DecoderConfigDescriptor`'s declared size includes the nested
    /// `DecSpecificInfo` (13 fixed + 4 = 17 bytes).
    fn esds() -> Vec<u8> {
        full_box(
            b"esds",
            0,
            0,
            &[
                0x03, 0x19, 0x00, 0x01, 0x00, // ES_Descr: es_id=1, flags=0
                0x04, 0x11, 0x40, 0x15, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x05, 0x02, 0x11, 0x90, // DecSpecificInfo
                0x06, 0x01, 0x02, // SLConfigDescr predefined=2
            ],
        )
    }

    /// `esds` v0 with a caller-chosen OTI and optional DecSpecificInfo payload.
    /// `dec_config` declared size covers only its fixed 13 bytes (DSI excluded),
    /// matching `DecoderConfigDescriptor::encode` in upstream.
    fn esds_with_oti(oti: u8, dsi: Option<&[u8]>) -> Vec<u8> {
        let mut dec = vec![
            0x04, 0x0d, oti, 0x15, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        ];
        if let Some(dsi) = dsi {
            dec.extend_from_slice(&[0x05, dsi.len() as u8]);
            dec.extend_from_slice(dsi);
        }
        let mut es = vec![0x03, 0x00, 0x00, 0x01, 0x00];
        es.extend_from_slice(&dec);
        es.extend_from_slice(&[0x06, 0x01, 0x02]);
        es[1] = (es.len() - 2) as u8;
        full_box(b"esds", 0, 0, &es)
    }

    /// `esds` v0 whose DecoderConfigDescriptor has no DecSpecificInfo.
    fn esds_no_dsi() -> Vec<u8> {
        esds_with_oti(0x40, None)
    }

    /// `esds` exercising all three optional ES flags.
    fn esds_all_flags() -> Vec<u8> {
        full_box(
            b"esds",
            0,
            0,
            &[
                0x03, 0x1f, 0x00, 0x02, 0xe5, // es_id=2, depends+url+ocr, priority=5
                0x00, 0x07, // depends_on_es_id=7
                0x01, 0x78, // url="x"
                0x00, 0x09, // ocr_es_id=9
                0x04, 0x11, 0x40, 0x15, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x05, 0x02, 0x11, 0x90, 0x06, 0x01, 0x02,
            ],
        )
    }

    fn dfla(blocks: &[Vec<u8>]) -> Vec<u8> {
        let mut body = Vec::new();
        for b in blocks {
            body.extend_from_slice(b);
        }
        full_box(b"dfLa", 0, 0, &body)
    }

    fn flac_block(last: bool, block_type: u8, data: &[u8]) -> Vec<u8> {
        let mut v = vec![(if last { 0x80 } else { 0x00 }) | block_type];
        v.extend_from_slice(&(data.len() as u32).to_be_bytes()[1..]);
        v.extend_from_slice(data);
        v
    }

    let streaminfo = flac_block(false, 0, &[0xAB; 34]);
    let padding_last = flac_block(true, 1, &[]);

    let visual = visual_fields(1, 640, 480);
    let audio = audio_fields(1, 2, 16, 48000 << 16);

    let mut cases: Vec<(&'static str, Vec<u8>)> = Vec::new();

    // --- valid round-trips ---
    cases.push((
        "avc1_basic",
        entry(b"avc1", &visual, &[avcc(100, true)]),
    ));
    cases.push((
        "avc1_profile66_no_tail",
        entry(b"avc1", &visual, &[avcc(66, false)]),
    ));
    cases.push((
        "avc1_unknown_children_ordered",
        entry(
            b"avc1",
            &visual,
            &[
                raw_box(b"pasp", &[0, 0, 0, 1, 0, 0, 0, 1]),
                avcc(66, false),
                raw_box(b"btrt", &[0, 0, 0, 0]),
            ],
        ),
    ));
    cases.push((
        "avc1_duplicate_avcc_second_unknown",
        entry(b"avc1", &visual, &[avcc(66, false), avcc(100, true)]),
    ));
    cases.push((
        "hev1_basic",
        entry(b"hev1", &visual, &[hvcc()]),
    ));
    cases.push((
        "hvc1_basic",
        entry(b"hvc1", &visual, &[hvcc()]),
    ));
    cases.push(("vp08_basic", entry(b"vp08", &visual, &[vpcc()])));
    cases.push(("vp09_basic", entry(b"vp09", &visual, &[vpcc()])));
    cases.push(("av01_basic", entry(b"av01", &visual, &[av1c()])));
    cases.push(("opus_basic", entry(b"Opus", &audio, &[dops()])));
    cases.push(("mp4a_basic", entry(b"mp4a", &audio, &[esds()])));
    cases.push((
        "mp4a_esds_all_flags",
        entry(b"mp4a", &audio, &[esds_all_flags()]),
    ));
    cases.push((
        "flac_basic",
        entry(
            b"fLaC",
            &audio,
            &[dfla(&[streaminfo.clone(), padding_last.clone()])],
        ),
    ));
    cases.push(("unknown_zzzz", raw_box(b"zzzz", &[0xaa, 0xbb])));

    // --- decode succeeds, re-encode fails (upstream behaviour) ---
    cases.push((
        "avc1_profile100_no_tail",
        entry(b"avc1", &visual, &[avcc(100, false)]),
    ));

    // --- decode errors ---
    cases.push(("avc1_missing_avcc", entry(b"avc1", &visual, &[])));
    cases.push(("hev1_missing_hvcc", entry(b"hev1", &visual, &[])));
    cases.push(("vp09_missing_vpcc", entry(b"vp09", &visual, &[])));
    cases.push(("av01_missing_av1c", entry(b"av01", &visual, &[])));
    cases.push(("opus_missing_dops", entry(b"Opus", &audio, &[])));
    cases.push(("mp4a_missing_esds", entry(b"mp4a", &audio, &[])));
    cases.push(("flac_missing_dfla", entry(b"fLaC", &audio, &[])));
    cases.push(("avc1_truncated_fields", {
        let mut v = entry(b"avc1", &visual[..40], &[]);
        let len = v.len() as u32;
        v[..4].copy_from_slice(&len.to_be_bytes());
        v
    }));
    cases.push(("avc1_dref_zero", {
        let mut fields = visual.clone();
        fields[6] = 0;
        fields[7] = 0;
        entry(b"avc1", &fields, &[avcc(66, false)])
    }));
    cases.push(("avcc_bad_version", {
        let mut c = avcc(66, false);
        c[8] = 2;
        entry(b"avc1", &visual, &[c])
    }));
    cases.push(("hvcc_bad_version", {
        let mut c = hvcc();
        c[8] = 2;
        entry(b"hev1", &visual, &[c])
    }));
    cases.push(("vpcc_bad_version", {
        let mut c = vpcc();
        c[8] = 2;
        entry(b"vp09", &visual, &[c])
    }));
    cases.push(("av1c_bad_marker", {
        entry(b"av01", &visual, &[raw_box(b"av1C", &[0x01, 0, 0, 0])])
    }));
    cases.push(("av1c_bad_version", {
        entry(b"av01", &visual, &[raw_box(b"av1C", &[0x82, 0, 0, 0])])
    }));
    cases.push(("dops_bad_version", {
        let mut c = dops();
        c[8] = 1;
        entry(b"Opus", &audio, &[c])
    }));
    cases.push(("dops_bad_mapping_family", {
        let mut c = dops();
        *c.last_mut().unwrap() = 1;
        entry(b"Opus", &audio, &[c])
    }));
    cases.push(("dfla_bad_version", {
        let mut c = dfla(&[streaminfo.clone(), padding_last.clone()]);
        c[8] = 1;
        entry(b"fLaC", &audio, &[c])
    }));
    cases.push(("dfla_empty", entry(b"fLaC", &audio, &[dfla(&[])])));
    cases.push(("dfla_first_not_streaminfo", {
        entry(b"fLaC", &audio, &[dfla(&[padding_last.clone()])])
    }));
    cases.push(("dfla_trailing_after_last", {
        entry(
            b"fLaC",
            &audio,
            &[dfla(&[
                streaminfo.clone(),
                padding_last.clone(),
                vec![0xaa],
            ])],
        )
    }));
    cases.push(("esds_sl_predefined_bad", {
        let mut c = esds();
        *c.last_mut().unwrap() = 1;
        entry(b"mp4a", &audio, &[c])
    }));
    cases.push(("mp4a_no_dsi", entry(b"mp4a", &audio, &[esds_no_dsi()])));
    cases.push((
        "mp4a_oti_6b",
        entry(b"mp4a", &audio, &[esds_with_oti(0x6b, None)]),
    ));
    cases.push((
        "mp4a_aot31_escape",
        entry(b"mp4a", &audio, &[esds_with_oti(0x40, Some(&[0xf8, 0x40]))]),
    ));
    cases.push((
        "mp4a_aot31_ext_bits",
        entry(b"mp4a", &audio, &[esds_with_oti(0x40, Some(&[0xf9, 0x20]))]),
    ));
    cases.push((
        "mp4a_asc_empty",
        entry(b"mp4a", &audio, &[esds_with_oti(0x40, Some(&[]))]),
    ));
    cases.push((
        "mp4a_asc_truncated",
        entry(b"mp4a", &audio, &[esds_with_oti(0x40, Some(&[0xf8]))]),
    ));
    // HEVC codec-string boundary cases (issue 0011): profile space letters,
    // compat=0, all-zero / trailing-zero constraints, and the high tier.
    cases.push((
        "hev1_space_b",
        entry(
            b"hev1",
            &visual,
            &[hvcc_with(0x81, 0x60000000, &[0x90, 0, 0, 0, 0, 0], 120)],
        ),
    ));
    cases.push((
        "hev1_tier_h_space_a",
        entry(
            b"hev1",
            &visual,
            &[hvcc_with(0x62, 0x60000000, &[0x90, 0, 0, 0, 0, 0], 93)],
        ),
    ));
    cases.push((
        "hev1_compat_zero",
        entry(
            b"hev1",
            &visual,
            &[hvcc_with(0x01, 0, &[0x90, 0, 0, 0, 0, 0], 93)],
        ),
    ));
    cases.push((
        "hev1_constraint_all_zero",
        entry(
            b"hev1",
            &visual,
            &[hvcc_with(0x01, 0x60000000, &[0; 6], 93)],
        ),
    ));
    cases.push((
        "hev1_constraint_trailing_zeros",
        entry(
            b"hev1",
            &visual,
            &[hvcc_with(0x01, 0x60000000, &[0x90, 0, 1, 0, 0, 0], 93)],
        ),
    ));
    // AV1 bit-depth branches and VP9 two-digit fields (issue 0011).
    cases.push((
        "av01_level1",
        entry(b"av01", &visual, &[av1c_with(0, 1, 0, 0, 0)]),
    ));
    cases.push((
        "av01_profile2_12bit",
        entry(b"av01", &visual, &[av1c_with(2, 4, 1, 1, 1)]),
    ));
    cases.push((
        "av01_profile2_10bit",
        entry(b"av01", &visual, &[av1c_with(2, 4, 1, 1, 0)]),
    ));
    cases.push((
        "av01_high_bitdepth",
        entry(b"av01", &visual, &[av1c_with(0, 0, 0, 1, 0)]),
    ));
    cases.push((
        "vp09_level31",
        entry(b"vp09", &visual, &[vpcc_with(0, 31, 8)]),
    ));
    cases.push(("avcc_sps_too_large", {
        let mut c = avcc(66, false);
        // declared SPS length exceeds the remaining payload
        c[14] = 0;
        c[15] = 0x7f;
        entry(b"avc1", &visual, &[c])
    }));
    cases.push(("hvcc_nalu_too_large", {
        let mut c = hvcc();
        // one array with a NALU whose declared length exceeds the payload
        c[30] = 1;
        c.extend_from_slice(&[0xa0, 0x00, 0x01, 0x7f, 0xff, 0xaa]);
        let len = c.len() as u32;
        c[..4].copy_from_slice(&len.to_be_bytes());
        entry(b"hev1", &visual, &[c])
    }));

    cases
}

/// Runs the fixed sample-entry case table and emits the normalised JSON.
fn run_sample_entry_cases() -> String {
    let cases = sample_entry_cases();
    let mut items: Vec<String> = Vec::new();
    for (name, input) in &cases {
        let mut entry = format!("{{\"name\": \"{name}\", \"input\": \"{}\"", hex(input));
        match sample_entry_outcome(input) {
            SampleEntryOutcome::Ok { snapshot, encoded } => {
                let _ = write!(
                    entry,
                    ", \"ok\": true, \"snapshot\": {}, \"encoded\": \"{}\"",
                    snapshot_json(&snapshot),
                    hex(&encoded)
                );
            }
            SampleEntryOutcome::EncodeErr {
                snapshot,
                kind,
                reason,
            } => {
                let _ = write!(
                    entry,
                    ", \"ok\": true, \"snapshot\": {}, \"encoded\": null, \"encode_error_kind\": \"{kind}\", \"encode_error_reason\": {}",
                    snapshot_json(&snapshot),
                    json_string_to(&reason)
                );
            }
            SampleEntryOutcome::DecodeErr { kind, reason } => {
                let _ = write!(
                    entry,
                    ", \"ok\": false, \"error_kind\": \"{kind}\", \"reason\": {}",
                    json_string_to(&reason)
                );
            }
        }
        entry.push('}');
        items.push(entry);
    }
    format!(
        "{{\"schema\": {SCHEMA_VERSION}, \"upstream_sha\": \"{UPSTREAM_SHA}\", \"cases\": [{}]}}",
        items.join(", ")
    )
}

/// Emits the MoonBit case-table file consumed by
/// `src/boxes/sample_entry_oracle_test.mbt`.
fn sample_entry_moonbit_cases() -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- sample-entries-cases --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (sample_entry_cases)."
    );
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(
        out,
        "// DO NOT EDIT MANUALLY. Regenerate (canonical formatting is part of the file):"
    );
    let _ = writeln!(
        out,
        "//   (cd tools/oracle && cargo run -- sample-entries-cases --moonbit) \\"
    );
    let _ = writeln!(
        out,
        "//     > src/boxes/sample_entry_oracle_cases_test.mbt"
    );
    let _ = writeln!(out, "//   moon fmt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `sample-entries-cases` が返すケース表（生成物）。"
    );
    let _ = writeln!(out, "///");
    let _ = writeln!(
        out,
        "/// 型は `src/boxes/sample_entry_oracle_test.mbt` で定義する。手で編集しない。"
    );
    let _ = writeln!(
        out,
        "let oracle_sample_entry_cases : Array[OracleSampleEntryCase] = ["
    );
    for (name, input) in &sample_entry_cases() {
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: \"{name}\",");
        let _ = writeln!(out, "    input: {},", moonbit_bytes(input));
        match sample_entry_outcome(input) {
            SampleEntryOutcome::Ok { snapshot, encoded } => {
                let _ = writeln!(out, "    ok: true,");
                write_moonbit_snapshot(&mut out, &snapshot, 4);
                let _ = writeln!(out, "    error_kind: \"\",");
                let _ = writeln!(out, "    reason: \"\",");
                let _ = writeln!(out, "    encoded: {},", moonbit_bytes(&encoded));
                let _ = writeln!(out, "    encode_error_kind: \"\",");
                let _ = writeln!(out, "    encode_error_reason: \"\",");
            }
            SampleEntryOutcome::EncodeErr {
                snapshot,
                kind,
                reason,
            } => {
                let _ = writeln!(out, "    ok: true,");
                write_moonbit_snapshot(&mut out, &snapshot, 4);
                let _ = writeln!(out, "    error_kind: \"\",");
                let _ = writeln!(out, "    reason: \"\",");
                let _ = writeln!(out, "    encoded: b\"\",");
                let _ = writeln!(out, "    encode_error_kind: \"{kind}\",");
                let _ = writeln!(
                    out,
                    "    encode_error_reason: {},",
                    moonbit_string(&reason)
                );
            }
            SampleEntryOutcome::DecodeErr { kind, reason } => {
                let _ = writeln!(out, "    ok: false,");
                let _ = writeln!(out, "    snapshot: [],");
                let _ = writeln!(out, "    error_kind: \"{kind}\",");
                let _ = writeln!(out, "    reason: {},", moonbit_string(&reason));
                let _ = writeln!(out, "    encoded: b\"\",");
                let _ = writeln!(out, "    encode_error_kind: \"\",");
                let _ = writeln!(out, "    encode_error_reason: \"\",");
            }
        }
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}

/// Extracts every track's `stsd` entries from every fixture and re-encodes
/// each entry with upstream (panics on failure: generation must not silently
/// emit stale data).
fn sample_entry_fixture_entries() -> Vec<(&'static str, usize, usize, Vec<u8>)> {
    let mut out = Vec::new();
    for (name, data) in SAMPLE_TABLE_FIXTURES {
        let moov_bytes =
            extract_top_level_box(data, b"moov").unwrap_or_else(|(kind, reason)| {
                panic!("{name}: top-level moov extraction failed: {kind}: {reason}")
            });
        let (moov, _) = MoovBox::decode(&moov_bytes).unwrap_or_else(|e| {
            panic!(
                "{name}: moov decode failed: {}: {}",
                error_kind_str(e.kind),
                e.reason
            )
        });
        for (track_index, trak) in moov.trak_boxes.iter().enumerate() {
            for (entry_index, entry) in trak
                .mdia_box
                .minf_box
                .stbl_box
                .stsd_box
                .entries
                .iter()
                .enumerate()
            {
                let encoded = entry.encode_to_vec().unwrap_or_else(|e| {
                    panic!(
                        "{name} track {track_index} entry {entry_index}: encode failed: {}: {}",
                        error_kind_str(e.kind),
                        e.reason
                    )
                });
                out.push((*name, track_index, entry_index, encoded));
            }
        }
    }
    out
}

/// Emits the fixture differential data consumed by
/// `src/boxes/sample_entry_oracle_test.mbt`.
fn sample_entry_moonbit_fixtures() -> String {
    let fixtures = sample_entry_fixture_entries();
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- sample-entries-fixtures --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (SAMPLE_TABLE_FIXTURES)."
    );
    let _ = writeln!(
        out,
        "// Fixtures (per-entry `stsd` sample entries re-encoded by upstream):"
    );
    for (name, track_index, entry_index, entry) in &fixtures {
        let _ = writeln!(
            out,
            "//   {name} track {track_index} entry {entry_index}: {} bytes, sha256 {}",
            entry.len(),
            sha256_hex(entry)
        );
    }
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(
        out,
        "// DO NOT EDIT MANUALLY. Regenerate (canonical formatting is part of the file):"
    );
    let _ = writeln!(
        out,
        "//   (cd tools/oracle && cargo run -- sample-entries-fixtures --moonbit) \\"
    );
    let _ = writeln!(
        out,
        "//     > src/boxes/sample_entry_oracle_fixtures_test.mbt"
    );
    let _ = writeln!(out, "//   moon fmt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `sample-entries-fixtures` が返す fixture 走査（生成物）。"
    );
    let _ = writeln!(out, "///");
    let _ = writeln!(
        out,
        "/// 型は `src/boxes/sample_entry_oracle_test.mbt` で定義する。手で編集しない。"
    );
    let _ = writeln!(
        out,
        "let oracle_sample_entry_fixtures : Array[OracleSampleEntryFixture] = ["
    );
    for (name, track_index, entry_index, entry_bytes) in &fixtures {
        let snapshot = match sample_entry_outcome(entry_bytes) {
            SampleEntryOutcome::Ok { snapshot, .. } => snapshot,
            SampleEntryOutcome::EncodeErr { kind, reason, .. }
            | SampleEntryOutcome::DecodeErr { kind, reason } => panic!(
                "{name} track {track_index} entry {entry_index}: re-decode failed: {kind}: {reason}"
            ),
        };
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: \"{name}\",");
        let _ = writeln!(out, "    track_index: {track_index},");
        let _ = writeln!(out, "    entry_index: {entry_index},");
        let _ = writeln!(out, "    input: {},", moonbit_bytes(entry_bytes));
        write_moonbit_snapshot(&mut out, &snapshot, 4);
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}

/// Codec-string case table: every sample-entry case plus every fixture entry
/// (issue 0011). `decode_ok=false` rows only carry the entry-level decode
/// outcome — the codec string step is skipped on purpose.
fn codec_string_cases() -> Vec<(String, Vec<u8>)> {
    let mut out: Vec<(String, Vec<u8>)> = sample_entry_cases()
        .iter()
        .map(|(name, input)| (name.to_string(), input.clone()))
        .collect();
    for (name, track_index, entry_index, bytes) in sample_entry_fixture_entries() {
        out.push((
            format!("{name}/track{track_index}/entry{entry_index}"),
            bytes,
        ));
    }
    out
}

/// One codec-string observation for the MoonBit differential test.
struct CodecStringOutcome {
    decode_ok: bool,
    codec_string: Option<String>,
    error_kind: &'static str,
    reason: String,
}

fn codec_string_outcome(input: &[u8]) -> CodecStringOutcome {
    let entry = match SampleEntry::decode(input) {
        Ok((entry, _)) => entry,
        Err(error) => {
            return CodecStringOutcome {
                decode_ok: false,
                codec_string: None,
                error_kind: error_kind_str(error.kind),
                reason: error.reason,
            };
        }
    };
    match shiguredo_mp4::codec_string::from_sample_entry(&entry) {
        Ok(s) => CodecStringOutcome {
            decode_ok: true,
            codec_string: Some(s),
            error_kind: "",
            reason: String::new(),
        },
        Err(error) => CodecStringOutcome {
            decode_ok: true,
            codec_string: None,
            error_kind: error_kind_str(error.kind),
            reason: error.reason,
        },
    }
}

/// Runs the codec-string case table and emits the normalised JSON.
fn run_codec_string_cases() -> String {
    let cases = codec_string_cases();
    let mut items: Vec<String> = Vec::new();
    for (name, input) in &cases {
        let mut entry = format!("{{\"name\": ");
        json_string(name, &mut entry);
        let _ = write!(entry, ", \"input\": \"{}\", ", hex(input));
        let outcome = codec_string_outcome(input);
        let _ = write!(entry, "\"decode_ok\": {}", outcome.decode_ok);
        match &outcome.codec_string {
            Some(s) => {
                entry.push_str(", \"codec_string\": ");
                json_string(s, &mut entry);
            }
            None => {
                let _ = write!(
                    entry,
                    ", \"codec_string\": null, \"error_kind\": \"{}\", \"reason\": {}",
                    outcome.error_kind,
                    json_string_to(&outcome.reason)
                );
            }
        }
        entry.push('}');
        items.push(entry);
    }
    format!(
        "{{\"schema\": {SCHEMA_VERSION}, \"upstream_sha\": \"{UPSTREAM_SHA}\", \"cases\": [{}]}}",
        items.join(", ")
    )
}

/// Emits the MoonBit case-table file consumed by
/// `src/codec_string/codec_string_oracle_test.mbt`.
fn codec_string_moonbit_cases() -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- codec-strings-cases --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (sample_entry_cases + SAMPLE_TABLE_FIXTURES)."
    );
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(
        out,
        "// DO NOT EDIT MANUALLY. Regenerate (canonical formatting is part of the file):"
    );
    let _ = writeln!(
        out,
        "//   (cd tools/oracle && cargo run -- codec-strings-cases --moonbit) \\"
    );
    let _ = writeln!(
        out,
        "//     > src/codec_string/codec_string_oracle_cases_test.mbt"
    );
    let _ = writeln!(out, "//   moon fmt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `codec-strings-cases` が返すケース表（生成物）。"
    );
    let _ = writeln!(out, "///");
    let _ = writeln!(
        out,
        "/// 型は `src/codec_string/codec_string_oracle_test.mbt` で定義する。手で編集しない。"
    );
    let _ = writeln!(
        out,
        "let oracle_codec_string_cases : Array[OracleCodecStringCase] = ["
    );
    for (name, input) in &codec_string_cases() {
        let outcome = codec_string_outcome(input);
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: {},", moonbit_string(name));
        let _ = writeln!(out, "    input: {},", moonbit_bytes(input));
        let _ = writeln!(
            out,
            "    decode_ok: {},",
            if outcome.decode_ok { "true" } else { "false" }
        );
        match outcome.codec_string {
            Some(s) => {
                let _ = writeln!(out, "    codec_string: {},", moonbit_string(&s));
                let _ = writeln!(out, "    error_kind: \"\",");
                let _ = writeln!(out, "    reason: \"\",");
            }
            None => {
                let _ = writeln!(out, "    codec_string: \"\",");
                let _ = writeln!(out, "    error_kind: \"{}\",", outcome.error_kind);
                let _ = writeln!(
                    out,
                    "    reason: {},",
                    moonbit_string(&outcome.reason)
                );
            }
        }
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}

/// `sample-entries <mp4-file>` — per-track `stsd` entry snapshots.
fn run_sample_entries(path: &str) -> Result<String, String> {
    let data = fs::read(path).map_err(|e| format!("failed to read {path}: {e}"))?;
    let name = Path::new(path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_owned();

    let mut input = String::from("{");
    input.push_str("\"name\": ");
    json_string(&name, &mut input);
    let _ = write!(input, ", \"size\": \"{}\", \"sha256\": ", data.len());
    json_string(&sha256_hex(&data), &mut input);
    input.push('}');

    let (tracks, moov_error) = match extract_top_level_box(&data, b"moov") {
        Ok(moov) => match MoovBox::decode(&moov) {
            Ok((moov_box, _)) => (sample_entries_json_for_moov(&moov_box), String::from("null")),
            Err(error) => (
                String::from("[]"),
                format!(
                    "{{\"error_kind\": \"{}\", \"reason\": {}}}",
                    error_kind_str(error.kind),
                    json_string_to(&error.reason)
                ),
            ),
        },
        Err((kind, reason)) => (
            String::from("[]"),
            format!(
                "{{\"error_kind\": \"{kind}\", \"reason\": {}}}",
                json_string_to(&reason)
            ),
        ),
    };

    let parts = [
        format!("  \"schema_version\": {SCHEMA_VERSION}"),
        format!("  \"upstream_sha\": \"{UPSTREAM_SHA}\""),
        format!("  \"input\": {input}"),
        format!("  \"tracks\": {tracks}"),
        format!("  \"moov_error\": {moov_error}"),
    ];
    Ok(format!("{{\n{}\n}}\n", parts.join(",\n")))
}

/// Snapshots every track's `stsd` entries in a decoded `moov`.
fn sample_entries_json_for_moov(moov: &MoovBox) -> String {
    let mut tracks: Vec<String> = Vec::new();
    for (track_index, trak) in moov.trak_boxes.iter().enumerate() {
        let mut entries: Vec<String> = Vec::new();
        for (entry_index, entry) in trak
            .mdia_box
            .minf_box
            .stbl_box
            .stsd_box
            .entries
            .iter()
            .enumerate()
        {
            entries.push(format!(
                "{{\"entry_index\": {entry_index}, \"snapshot\": {}}}",
                snapshot_json(&sample_entry_snapshot(entry))
            ));
        }
        tracks.push(format!(
            "{{\"track_index\": {track_index}, \"entries\": [{}]}}",
            entries.join(", ")
        ));
    }
    format!("[{}]", tracks.join(", "))
}


/// Splits `data` into top-level box byte ranges, using only the box headers.
/// Stops at the first malformed/truncated header.
fn top_level_box_ranges(data: &[u8]) -> Vec<(usize, usize, [u8; 4])> {
    let mut out = Vec::new();
    let mut offset = 0usize;
    while offset + 8 <= data.len() {
        let box_type: [u8; 4] = data[offset + 4..offset + 8].try_into().unwrap();
        let size32 = u32::from_be_bytes(data[offset..offset + 4].try_into().unwrap()) as u64;
        let end = if size32 == 0 {
            data.len()
        } else if size32 == 1 {
            if offset + 16 > data.len() {
                break;
            }
            let largesize = u64::from_be_bytes(data[offset + 8..offset + 16].try_into().unwrap());
            offset.saturating_add(usize::try_from(largesize).unwrap_or(usize::MAX)).min(data.len())
        } else {
            offset.saturating_add(size32 as usize).min(data.len())
        };
        out.push((offset, end, box_type));
        if end <= offset {
            break;
        }
        offset = end;
    }
    out
}

/// Returns the raw bytes (header + payload) of the first top-level box of the
/// given type in `data`.
fn top_level_box_bytes(data: &[u8], wanted: &[u8; 4]) -> Vec<u8> {
    for &(start, end, ref box_type) in &top_level_box_ranges(data) {
        if box_type == wanted {
            return data[start..end].to_vec();
        }
    }
    Vec::new()
}

/// Case table for `kind-detector-cases`.
///
/// Covers the 9 upstream fixtures plus synthetic files exercising every
/// detector edge: non-faststart ordering (moov at end), unknown boxes,
/// largesize headers, size-0 boxes, missing moov, offset overflow, and
/// malformed headers.
fn kind_detector_cases() -> Vec<(String, Vec<u8>)> {
    let mp4 = SAMPLE_TABLE_FIXTURES
        .iter()
        .find(|(name, _)| *name == "black-h264-video.mp4")
        .expect("black-h264-video fixture")
        .1;
    let fmp4 = SAMPLE_TABLE_FIXTURES
        .iter()
        .find(|(name, _)| *name == "black-h264-fmp4.mp4")
        .expect("black-h264-fmp4 fixture")
        .1;
    let ftyp = top_level_box_bytes(mp4, b"ftyp");
    let mdat = top_level_box_bytes(mp4, b"mdat");
    let moov = top_level_box_bytes(mp4, b"moov");
    let moov_fmp4 = top_level_box_bytes(fmp4, b"moov");
    assert!(!ftyp.is_empty() && !mdat.is_empty() && !moov.is_empty() && !moov_fmp4.is_empty());
    let concat = |parts: &[&[u8]]| -> Vec<u8> { parts.concat() };

    let mut cases: Vec<(String, Vec<u8>)> = Vec::new();
    for &(name, data) in SAMPLE_TABLE_FIXTURES {
        cases.push((format!("fixture:{name}"), data.to_vec()));
    }

    // non-faststart: moov at the very end, after a large mdat
    cases.push(("moov_at_end".to_owned(), concat(&[&ftyp, &mdat, &moov])));
    cases.push((
        "moov_at_end_fmp4".to_owned(),
        concat(&[&ftyp, &mdat, &moov_fmp4]),
    ));

    // unknown top-level box before moov (skipped by header size only)
    let mut zzzz = Vec::new();
    zzzz.extend_from_slice(&16u32.to_be_bytes());
    zzzz.extend_from_slice(b"zzzz");
    zzzz.extend_from_slice(&[0u8; 8]);
    cases.push((
        "unknown_box_before_moov".to_owned(),
        concat(&[&ftyp, &zzzz, &moov]),
    ));

    // largesize-encoded box before moov
    let mut large = Vec::new();
    large.extend_from_slice(&1u32.to_be_bytes());
    large.extend_from_slice(b"free");
    large.extend_from_slice(&32u64.to_be_bytes());
    large.extend_from_slice(&[0u8; 16]);
    cases.push((
        "largesize_box_before_moov".to_owned(),
        concat(&[&ftyp, &large, &moov]),
    ));

    // moov encoded with size=0 (extends to EOF; must be last)
    let mut moov_zero = moov.clone();
    moov_zero[..4].copy_from_slice(&0u32.to_be_bytes());
    cases.push((
        "moov_size_zero_last".to_owned(),
        concat(&[&ftyp, &mdat, &moov_zero]),
    ));

    // no moov at all -> "moov box not found before EOF"
    cases.push(("moov_not_found".to_owned(), concat(&[&ftyp, &mdat])));

    // size=0 non-moov box before moov -> unsupported
    let zero_box = concat(&[&0u32.to_be_bytes(), b"free"]);
    cases.push((
        "zero_size_box_before_moov".to_owned(),
        concat(&[&ftyp, &zero_box, &moov]),
    ));

    // ftyp encoded with size=0 -> explicit error
    let mut ftyp_zero = ftyp.clone();
    ftyp_zero[..4].copy_from_slice(&0u32.to_be_bytes());
    cases.push(("ftyp_size_zero".to_owned(), concat(&[&ftyp_zero, &moov])));

    // first top-level box is not ftyp
    let mut free_box = Vec::new();
    free_box.extend_from_slice(&16u32.to_be_bytes());
    free_box.extend_from_slice(b"free");
    free_box.extend_from_slice(&[0u8; 8]);
    cases.push(("not_ftyp_first".to_owned(), concat(&[&free_box, &moov])));

    // file shorter than a box header
    cases.push(("truncated_header".to_owned(), ftyp[..10].to_vec()));

    // largesize u64::MAX box before moov -> offset overflow
    let mut huge = Vec::new();
    huge.extend_from_slice(&1u32.to_be_bytes());
    huge.extend_from_slice(b"xxxx");
    huge.extend_from_slice(&u64::MAX.to_be_bytes());
    cases.push(("offset_overflow".to_owned(), concat(&[&ftyp, &huge, &moov])));

    // declared size smaller than the header
    let mut bad_size = Vec::new();
    bad_size.extend_from_slice(&4u32.to_be_bytes());
    bad_size.extend_from_slice(b"abcd");
    cases.push((
        "invalid_box_size".to_owned(),
        concat(&[&ftyp, &bad_size, &moov]),
    ));

    // ftyp itself encoded as a largesize box
    let mut ftyp_large = Vec::new();
    ftyp_large.extend_from_slice(&1u32.to_be_bytes());
    ftyp_large.extend_from_slice(b"ftyp");
    ftyp_large.extend_from_slice(&(ftyp.len() as u64 + 8).to_be_bytes());
    ftyp_large.extend_from_slice(&ftyp[8..]);
    cases.push(("ftyp_largesize".to_owned(), concat(&[&ftyp_large, &moov])));

    cases
}

/// Drives `Mp4FileKindDetector` exactly like the upstream doc example: feeds
/// `input[position..]` for each `required_input()` until a terminal state.
/// Returns the full request log plus the final outcome.
fn run_kind_detector(
    input: &[u8],
) -> (Vec<(u64, Option<u64>)>, Result<Option<Mp4FileKind>, DemuxError>) {
    let mut detector = Mp4FileKindDetector::new();
    let mut requests = Vec::new();
    let mut steps = 0;
    let outcome = loop {
        match detector.required_input() {
            Some(required) => {
                steps += 1;
                if steps > MAX_INPUT_STEPS {
                    break Err(DemuxError::InvalidState(
                        "input feeding did not terminate",
                    ));
                }
                requests.push((required.position, required.size.map(|s| s as u64)));
                detector.handle_input(input_at(input, required.position));
            }
            None => break detector.file_kind(),
        }
    };
    (requests, outcome)
}


/// Renders bytes as `b"..."` literals split into <=4KiB chunks joined by `+`,
/// to keep generated lines below the compiler's warning threshold.
fn moonbit_bytes_chunked(data: &[u8]) -> String {
    let mut parts = Vec::new();
    for chunk in data.chunks(4096) {
        parts.push(moonbit_bytes(chunk));
    }
    if parts.is_empty() {
        parts.push("b\"\"".to_owned());
    }
    parts.join(" +\n      ")
}

/// `kind-detector-cases --moonbit` — request-log + outcome table for the
/// MP4/fMP4 kind detector, consumed by `src/demux/kind_detector_oracle_test.mbt`.
fn kind_detector_moonbit_cases() -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- kind-detector-cases --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (kind_detector_cases + SAMPLE_TABLE_FIXTURES)."
    );
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(
        out,
        "// DO NOT EDIT MANUALLY. Regenerate (canonical formatting is part of the file):"
    );
    let _ = writeln!(
        out,
        "//   (cd tools/oracle && cargo run -- kind-detector-cases --moonbit) \\\\"
    );
    let _ = writeln!(
        out,
        "//     > src/demux/kind_detector_oracle_cases_test.mbt"
    );
    let _ = writeln!(out, "//   moon fmt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `kind-detector-cases` が返すケース表（生成物）。"
    );
    let _ = writeln!(out, "///");
    let _ = writeln!(
        out,
        "/// 型は `src/demux/kind_detector_oracle_test.mbt` で定義する。手で編集しない。"
    );
    let _ = writeln!(
        out,
        "let oracle_kind_detector_cases : Array[OracleKindDetectorCase] = ["
    );
    for (name, input) in &kind_detector_cases() {
        let (requests, outcome) = run_kind_detector(input);
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: {},", moonbit_string(name));
        let _ = writeln!(out, "    input: {},", moonbit_bytes_chunked(input));
        let request_strs: Vec<String> = requests
            .iter()
            .map(|(position, size)| match size {
                Some(size) => format!("{{ position: {position}, size: Some({size}) }}"),
                None => format!("{{ position: {position}, size: None }}"),
            })
            .collect();
        let _ = writeln!(out, "    requests: [{}],", request_strs.join(", "));
        match &outcome {
            Ok(Some(kind)) => {
                let value = match kind {
                    Mp4FileKind::Mp4 => "mp4",
                    Mp4FileKind::FragmentedMp4 => "fragmented_mp4",
                };
                let _ = writeln!(out, "    outcome: \"{value}\",");
                let _ = writeln!(out, "    classification: \"\",");
                let _ = writeln!(out, "    error_kind: \"\",");
                let _ = writeln!(out, "    box_type: \"\",");
                let _ = writeln!(out, "    reason: \"\",");
            }
            Ok(None) => {
                let _ = writeln!(out, "    outcome: \"unverified\",");
                let _ = writeln!(out, "    classification: \"\",");
                let _ = writeln!(out, "    error_kind: \"\",");
                let _ = writeln!(out, "    box_type: \"\",");
                let _ = writeln!(out, "    reason: \"\",");
            }
            Err(e) => {
                let (classification, error_kind, box_type, reason) = match e {
                    DemuxError::DecodeError(e) => (
                        "decode_error",
                        error_kind_str(e.kind).to_owned(),
                        e.box_type
                            .map(|t| t.to_string())
                            .unwrap_or_default(),
                        e.reason.clone(),
                    ),
                    DemuxError::SampleTableError(e) => (
                        "sample_table_error",
                        String::new(),
                        String::new(),
                        e.to_string(),
                    ),
                    DemuxError::InvalidState(m) => (
                        "invalid_state",
                        String::new(),
                        String::new(),
                        m.to_string(),
                    ),
                    DemuxError::InputRequired(r) => (
                        "input_required",
                        String::new(),
                        String::new(),
                        format!(
                            "position={} size={:?}",
                            r.position, r.size
                        ),
                    ),
                };
                let _ = writeln!(out, "    outcome: \"error\",");
                let _ = writeln!(out, "    classification: \"{classification}\",");
                let _ = writeln!(out, "    error_kind: \"{error_kind}\",");
                let _ = writeln!(out, "    box_type: {},", moonbit_string(&box_type));
                let _ = writeln!(out, "    reason: {},", moonbit_string(&reason));
            }
        }
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}
// ===== `demux-cases` — Mp4FileDemuxer の凍結ケース表 =====

/// A single demux-cases entry: input bytes plus the upstream-observed
/// request log, track listing, forward/backward sample streams, and
/// optional seek probes.
struct DemuxCase {
    name: String,
    input: Vec<u8>,
    seek_probes: Vec<(u64, u32)>,
}

/// Outcome of driving `Mp4FileDemuxer` over a case input.
struct DemuxCaseOutcome {
    requests: Vec<(u64, Option<u64>)>,
    tracks: Vec<String>,
    tracks_error: String,
    samples: Vec<String>,
    samples_error: String,
    prev_samples: Vec<String>,
    prev_error: String,
    seek_results: Vec<(u64, u32, String)>,
}

/// Test `Avc1Box` mirroring upstream `create_avc1_sample_entry`.
fn demux_avc1_entry() -> SampleEntry {
    SampleEntry::Avc1(Avc1Box {
        visual: VisualSampleEntryFields {
            data_reference_index: VisualSampleEntryFields::DEFAULT_DATA_REFERENCE_INDEX,
            width: 640,
            height: 480,
            horizresolution: VisualSampleEntryFields::DEFAULT_HORIZRESOLUTION,
            vertresolution: VisualSampleEntryFields::DEFAULT_VERTRESOLUTION,
            frame_count: VisualSampleEntryFields::DEFAULT_FRAME_COUNT,
            compressorname: VisualSampleEntryFields::NULL_COMPRESSORNAME,
            depth: VisualSampleEntryFields::DEFAULT_DEPTH,
        },
        avcc_box: AvccBox {
            avc_profile_indication: 66,
            profile_compatibility: 0,
            avc_level_indication: 30,
            length_size_minus_one: Uint::new(3),
            sps_list: vec![],
            pps_list: vec![],
            chroma_format: None,
            bit_depth_luma_minus8: None,
            bit_depth_chroma_minus8: None,
            sps_ext_list: vec![],
        },
        unknown_boxes: vec![],
    })
}

/// Test `OpusBox` mirroring upstream `create_opus_sample_entry`.
fn demux_opus_entry() -> SampleEntry {
    SampleEntry::Opus(OpusBox {
        audio: AudioSampleEntryFields {
            data_reference_index: AudioSampleEntryFields::DEFAULT_DATA_REFERENCE_INDEX,
            channelcount: 2,
            samplesize: AudioSampleEntryFields::DEFAULT_SAMPLESIZE,
            samplerate: FixedPointNumber::new(48000u16, 0),
        },
        dops_box: DopsBox {
            output_channel_count: 2,
            pre_skip: 312,
            input_sample_rate: 48000,
            output_gain: 0,
        },
        unknown_boxes: vec![],
    })
}

/// Test `StppBox` mirroring upstream `create_stpp_sample_entry`.
fn demux_stpp_entry() -> SampleEntry {
    SampleEntry::Stpp(StppBox {
        data_reference_index: StppBox::DEFAULT_DATA_REFERENCE_INDEX,
        namespace: Utf8String::new("http://www.w3.org/ns/ttml").expect("no null byte"),
        schema_location: Utf8String::EMPTY,
        auxiliary_mime_types: Utf8String::EMPTY,
        unknown_boxes: vec![],
    })
}

/// Appends one sample at `offset` (which it advances by `data_size`).
fn append_demux_sample(
    muxer: &mut Mp4FileMuxer,
    offset: &mut u64,
    track_kind: TrackKind,
    sample_entry: Option<SampleEntry>,
    keyframe: bool,
    timescale: u32,
    duration: u32,
    composition_time_offset: Option<i64>,
    data_size: usize,
) {
    muxer
        .append_sample(&shiguredo_mp4::mux::Sample {
            track_kind,
            sample_entry,
            keyframe,
            timescale: std::num::NonZeroU32::new(timescale).expect("nonzero timescale"),
            duration,
            composition_time_offset,
            data_offset: *offset,
            data_size,
        })
        .expect("append_sample failed");
    *offset += data_size as u64;
}

/// Assembles the final file bytes from a finalized muxer, mirroring upstream
/// `build_file_data` (non-faststart: ftyp | mdat | moov).
fn assemble_muxed_file(muxer: &Mp4FileMuxer, data_end: u64) -> Vec<u8> {
    let finalized = muxer.finalized_boxes().expect("finalized boxes").clone();
    let initial = muxer.initial_boxes_bytes().to_vec();
    let mut file = vec![0u8; data_end as usize];
    file[..initial.len()].copy_from_slice(&initial);
    let mut max_end = data_end as usize;
    for (offset, bytes) in finalized.offset_and_bytes_pairs() {
        let end = offset as usize + bytes.len();
        if end > file.len() {
            file.resize(end, 0);
        }
        file[offset as usize..end].copy_from_slice(bytes);
        max_end = max_end.max(end);
    }
    file.truncate(max_end);
    file
}

/// Multi-track file: avc1 video (timescale 30) + Opus audio (timescale 48000),
/// mixed keyframe flags and v1 `ctts` offsets on the video track.
fn muxed_video_audio() -> Vec<u8> {
    let mut muxer = Mp4FileMuxer::new().expect("muxer");
    let mut offset = muxer.initial_boxes_bytes().len() as u64;
    let avc1 = demux_avc1_entry();
    let opus = demux_opus_entry();
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Video,
        Some(avc1),
        true,
        30,
        30,
        Some(4),
        100,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Audio,
        Some(opus),
        true,
        48000,
        48000,
        None,
        200,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Video,
        None,
        false,
        30,
        30,
        Some(0),
        110,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Audio,
        None,
        true,
        48000,
        48000,
        None,
        210,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Video,
        None,
        false,
        30,
        30,
        Some(-2),
        120,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Audio,
        None,
        true,
        48000,
        48000,
        None,
        220,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Audio,
        None,
        true,
        48000,
        48000,
        None,
        230,
    );
    muxer.finalize().expect("finalize");
    assemble_muxed_file(&muxer, offset)
}

/// Same two timescales but the audio track is appended first, so it becomes
/// track 1 and wins the same-second ties (upstream keeps the earliest track
/// in scan order on equal `Duration` keys).
fn muxed_audio_first() -> Vec<u8> {
    let mut muxer = Mp4FileMuxer::new().expect("muxer");
    let mut offset = muxer.initial_boxes_bytes().len() as u64;
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Audio,
        Some(demux_opus_entry()),
        true,
        48000,
        48000,
        None,
        200,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Video,
        Some(demux_avc1_entry()),
        true,
        30,
        30,
        None,
        100,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Audio,
        None,
        true,
        48000,
        48000,
        None,
        210,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Video,
        None,
        false,
        30,
        30,
        None,
        110,
    );
    muxer.finalize().expect("finalize");
    assemble_muxed_file(&muxer, offset)
}

/// Video-only file with a v0 `ctts` (non-negative offsets incl. explicit 0).
fn muxed_ctts_v0() -> Vec<u8> {
    let mut muxer = Mp4FileMuxer::new().expect("muxer");
    let mut offset = muxer.initial_boxes_bytes().len() as u64;
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Video,
        Some(demux_avc1_entry()),
        true,
        30,
        30,
        Some(0),
        100,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Video,
        None,
        false,
        30,
        30,
        Some(4),
        110,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Video,
        None,
        true,
        30,
        30,
        Some(0),
        120,
    );
    muxer.finalize().expect("finalize");
    assemble_muxed_file(&muxer, offset)
}

/// Video + subtitle (`stpp` entry → `subt` handler → `TrackKind::Subtitle`).
fn muxed_subtitle() -> Vec<u8> {
    let mut muxer = Mp4FileMuxer::new().expect("muxer");
    let mut offset = muxer.initial_boxes_bytes().len() as u64;
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Video,
        Some(demux_avc1_entry()),
        true,
        30,
        30,
        None,
        100,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Subtitle,
        Some(demux_stpp_entry()),
        true,
        1000,
        500,
        None,
        64,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Subtitle,
        None,
        true,
        1000,
        500,
        None,
        72,
    );
    muxer.finalize().expect("finalize");
    assemble_muxed_file(&muxer, offset)
}

/// Single-video file whose `hdlr` handler_type is patched to an unknown fourcc;
/// upstream skips the track entirely (`tracks` is empty).
fn muxed_unknown_handler() -> Vec<u8> {
    let mut file = {
        let mut muxer = Mp4FileMuxer::new().expect("muxer");
        let mut offset = muxer.initial_boxes_bytes().len() as u64;
        append_demux_sample(
            &mut muxer,
            &mut offset,
            TrackKind::Video,
            Some(demux_avc1_entry()),
            true,
            30,
            30,
            None,
            100,
        );
        muxer.finalize().expect("finalize");
        assemble_muxed_file(&muxer, offset)
    };
    // Locate the media `hdlr` box and overwrite handler_type ('hdlr'(4) +
    // version/flags(4) + pre_defined(4) => handler_type at +12).
    for i in 0..file.len().saturating_sub(16) {
        if &file[i..i + 4] == b"hdlr" && &file[i + 12..i + 16] == b"vide" {
            file[i + 12..i + 16].copy_from_slice(b"meta");
            break;
        }
    }
    file
}

/// Video-only faststart file (`moov` placed before `mdat`).
fn muxed_faststart() -> Vec<u8> {
    let options = Mp4FileMuxerOptions {
        reserved_moov_box_size: 8192,
        ..Default::default()
    };
    let mut muxer = Mp4FileMuxer::with_options(options).expect("muxer");
    let mut offset = muxer.initial_boxes_bytes().len() as u64;
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Video,
        Some(demux_avc1_entry()),
        true,
        30,
        30,
        None,
        100,
    );
    append_demux_sample(
        &mut muxer,
        &mut offset,
        TrackKind::Video,
        None,
        false,
        30,
        30,
        None,
        110,
    );
    muxer.finalize().expect("finalize");
    assemble_muxed_file(&muxer, offset)
}

/// Finalized with no samples at all (`moov` has no `trak`).
fn muxed_empty() -> Vec<u8> {
    let mut muxer = Mp4FileMuxer::new().expect("muxer");
    let offset = muxer.initial_boxes_bytes().len() as u64;
    muxer.finalize().expect("finalize");
    assemble_muxed_file(&muxer, offset)
}

/// A valid file whose `stsz` declared sample_count is bumped by one; the
/// `stsz` box decode itself fails with `InsufficientBuffer`.
fn corrupt_stsz(base: &[u8]) -> Vec<u8> {
    let mut file = base.to_vec();
    for i in 0..file.len().saturating_sub(16) {
        if &file[i..i + 4] == b"stsz" {
            // sample_count sits at 'stsz'(4) + version/flags(4) +
            // sample_size(4) => field at +12 relative to 'stsz' fourcc.
            let pos = i + 12;
            let count =
                u32::from_be_bytes([file[pos], file[pos + 1], file[pos + 2], file[pos + 3]]);
            file[pos..pos + 4].copy_from_slice(&(count + 1).to_be_bytes());
            break;
        }
    }
    file
}

/// A valid file whose `stsz` declared sample_count is shrunk by one; `stsz`
/// still decodes but the upstream `SampleTableAccessor` reports
/// `InconsistentSampleCount` and the demuxer surfaces `SampleTableError`.
fn corrupt_stsz_count_low(base: &[u8]) -> Vec<u8> {
    let mut file = base.to_vec();
    for i in 0..file.len().saturating_sub(16) {
        if &file[i..i + 4] == b"stsz" {
            let pos = i + 12;
            let count =
                u32::from_be_bytes([file[pos], file[pos + 1], file[pos + 2], file[pos + 3]]);
            file[pos..pos + 4].copy_from_slice(&(count - 1).to_be_bytes());
            break;
        }
    }
    file
}

/// Truncates the file just before the `moov` box so the demuxer runs into EOF.
fn without_moov(base: &[u8]) -> Vec<u8> {
    for i in 0..base.len().saturating_sub(4) {
        if &base[i..i + 4] == b"moov" {
            return base[..i - 4].to_vec();
        }
    }
    base.to_vec()
}

/// Patches the `ftyp` declared size to 0 (upstream treats it as "to EOF" and
/// still decodes the `ftyp` box normally — unlike the kind detector).
fn with_zero_size_ftyp(base: &[u8]) -> Vec<u8> {
    let mut file = base.to_vec();
    if &file[4..8] == b"ftyp" {
        file[0..4].copy_from_slice(&0u32.to_be_bytes());
    }
    file
}

/// Overwrites the leading `ftyp` fourcc so the first box is not `ftyp`.
fn with_renamed_ftyp(base: &[u8]) -> Vec<u8> {
    let mut file = base.to_vec();
    if &file[4..8] == b"ftyp" {
        file[4..8].copy_from_slice(b"free");
    }
    file
}

/// The full demux-cases table: checked-in fixtures plus synthetic inputs.
fn demux_cases(video_audio: &[u8]) -> Vec<DemuxCase> {
    let mut cases = Vec::new();
    for (name, data) in SAMPLE_TABLE_FIXTURES {
        cases.push(DemuxCase {
            name: format!("fixture:{name}"),
            input: data.to_vec(),
            seek_probes: vec![],
        });
    }

    cases.push(DemuxCase {
        name: "muxed_video_audio".to_owned(),
        input: video_audio.to_vec(),
        seek_probes: vec![(0, 0), (1, 0), (1, 500_000_000), (100, 0)],
    });
    cases.push(DemuxCase {
        name: "muxed_audio_first".to_owned(),
        input: muxed_audio_first(),
        seek_probes: vec![(1, 0)],
    });
    cases.push(DemuxCase {
        name: "muxed_ctts_v0".to_owned(),
        input: muxed_ctts_v0(),
        seek_probes: vec![],
    });
    cases.push(DemuxCase {
        name: "muxed_subtitle".to_owned(),
        input: muxed_subtitle(),
        seek_probes: vec![],
    });
    cases.push(DemuxCase {
        name: "muxed_unknown_handler".to_owned(),
        input: muxed_unknown_handler(),
        seek_probes: vec![],
    });
    cases.push(DemuxCase {
        name: "muxed_faststart".to_owned(),
        input: muxed_faststart(),
        seek_probes: vec![],
    });
    cases.push(DemuxCase {
        name: "muxed_empty".to_owned(),
        input: muxed_empty(),
        seek_probes: vec![],
    });
    cases.push(DemuxCase {
        name: "corrupt_stsz".to_owned(),
        input: corrupt_stsz(video_audio),
        seek_probes: vec![],
    });
    cases.push(DemuxCase {
        name: "corrupt_stsz_count_low".to_owned(),
        input: corrupt_stsz_count_low(video_audio),
        seek_probes: vec![],
    });
    cases.push(DemuxCase {
        name: "moov_missing".to_owned(),
        input: without_moov(video_audio),
        seek_probes: vec![],
    });
    cases.push(DemuxCase {
        name: "ftyp_size_zero".to_owned(),
        input: with_zero_size_ftyp(video_audio),
        seek_probes: vec![],
    });
    cases.push(DemuxCase {
        name: "not_ftyp_first".to_owned(),
        input: with_renamed_ftyp(video_audio),
        seek_probes: vec![],
    });
    cases
}

/// Slices `data` to exactly the requested range (clamped at EOF), so the
/// request log proves that `mdat` payloads are never needed.
fn required_slice<'a>(data: &'a [u8], required: &RequiredInput) -> &'a [u8] {
    let start = usize::try_from(required.position)
        .unwrap_or(usize::MAX)
        .min(data.len());
    match required.size {
        Some(size) => {
            let end = start
                .saturating_add(usize::try_from(size).unwrap_or(usize::MAX))
                .min(data.len());
            &data[start..end]
        }
        None => &data[start..],
    }
}

/// Renders a `DemuxError` as the frozen
/// `classification=...,key=value,...` line used by the case table.
fn demux_error_line(error: &DemuxError) -> String {
    match error {
        DemuxError::DecodeError(e) => format!(
            "classification=decode_error,error_kind={},box_type={},reason={}",
            error_kind_str(e.kind),
            e.box_type.map(|t| t.to_string()).unwrap_or_default(),
            e.reason,
        ),
        DemuxError::SampleTableError(e) => {
            format!("classification=sample_table_error,reason={e}")
        }
        DemuxError::InvalidState(m) => {
            format!("classification=invalid_state,reason={m}")
        }
        DemuxError::InputRequired(r) => format!(
            "classification=input_required,position={},size={}",
            r.position,
            r.size
                .map(|s| s.to_string())
                .unwrap_or_else(|| "none".to_owned()),
        ),
    }
}

/// Frozen one-line description of a demuxed sample.
fn demux_sample_line(sample: &shiguredo_mp4::demux::Sample) -> String {
    let entry = match &sample.sample_entry {
        Some(entry) => entry.box_type().to_string(),
        None => "none".to_owned(),
    };
    let cto = match sample.composition_time_offset {
        Some(v) => v.to_string(),
        None => "none".to_owned(),
    };
    format!(
        "track_id={},sample_entry={},keyframe={},dts={},duration={},pts_offset={},data_offset={},data_size={}",
        sample.track.track_id,
        entry,
        sample.keyframe,
        sample.timestamp,
        sample.duration,
        cto,
        sample.data_offset,
        sample.data_size,
    )
}

/// Frozen one-line description of a track.
fn demux_track_line(track: &shiguredo_mp4::demux::TrackInfo) -> String {
    format!(
        "track_id={},kind={},duration={},timescale={}",
        track.track_id,
        track_kind_str(track.kind),
        track.duration,
        track.timescale.get(),
    )
}

/// Feeds `Mp4FileDemuxer` with exactly the requested ranges and records the
/// observable upstream behavior for the case table.
fn drive_demux_case(case: &DemuxCase) -> DemuxCaseOutcome {
    let mut demuxer = Mp4FileDemuxer::new();
    let mut requests = Vec::new();
    for _ in 0..MAX_INPUT_STEPS {
        match demuxer.required_input() {
            Some(required) => {
                requests.push((required.position, required.size.map(|s| s as u64)));
                let data = required_slice(&case.input, &required);
                demuxer.handle_input(Input {
                    position: required.position,
                    data,
                });
            }
            None => break,
        }
    }

    let (tracks, tracks_error) = match demuxer.tracks() {
        Ok(tracks) => (tracks.iter().map(demux_track_line).collect(), String::new()),
        Err(e) => (Vec::new(), demux_error_line(&e)),
    };

    let mut samples = Vec::new();
    let mut samples_error = String::new();
    loop {
        match demuxer.next_sample() {
            Ok(Some(sample)) => samples.push(demux_sample_line(&sample)),
            Ok(None) => break,
            Err(e) => {
                samples_error = demux_error_line(&e);
                break;
            }
        }
        if samples.len() as u64 > MAX_SAMPLES {
            samples_error =
                "classification=input_required,reason=sample enumeration did not terminate"
                    .to_owned();
            break;
        }
    }

    let mut prev_samples = Vec::new();
    let mut prev_error = String::new();
    loop {
        match demuxer.prev_sample() {
            Ok(Some(sample)) => prev_samples.push(demux_sample_line(&sample)),
            Ok(None) => break,
            Err(e) => {
                prev_error = demux_error_line(&e);
                break;
            }
        }
        if prev_samples.len() as u64 > MAX_SAMPLES {
            prev_error =
                "classification=input_required,reason=sample enumeration did not terminate"
                    .to_owned();
            break;
        }
    }

    let mut seek_results = Vec::new();
    for &(secs, nanos) in &case.seek_probes {
        let expected = match demuxer.seek(std::time::Duration::new(secs, nanos)) {
            Ok(()) => match demuxer.next_sample() {
                Ok(Some(sample)) => demux_sample_line(&sample),
                Ok(None) => "none".to_owned(),
                Err(e) => format!("error:{}", demux_error_line(&e)),
            },
            Err(e) => format!("error:{}", demux_error_line(&e)),
        };
        seek_results.push((secs, nanos, expected));
    }

    DemuxCaseOutcome {
        requests,
        tracks,
        tracks_error,
        samples,
        samples_error,
        prev_samples,
        prev_error,
        seek_results,
    }
}

/// `demux-cases --moonbit` — request logs, track/sample streams, and seek
/// probes frozen from the upstream demuxer, consumed by
/// `src/demux/mp4_file_demux_oracle_test.mbt`.
fn demux_cases_moonbit() -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "// Generated by `cargo run -- demux-cases --moonbit` (tools/oracle)."
    );
    let _ = writeln!(
        out,
        "// Source of truth: tools/oracle/src/main.rs (demux_cases + SAMPLE_TABLE_FIXTURES)."
    );
    let _ = writeln!(out, "// Upstream: shiguredo/mp4-rs@{UPSTREAM_SHA}");
    let _ = writeln!(
        out,
        "// DO NOT EDIT MANUALLY. Regenerate (canonical formatting is part of the file):"
    );
    let _ = writeln!(
        out,
        "//   (cd tools/oracle && cargo run -- demux-cases --moonbit) \\\\"
    );
    let _ = writeln!(
        out,
        "//     > src/demux/mp4_file_demux_oracle_cases_test.mbt"
    );
    let _ = writeln!(out, "//   moon fmt");
    let _ = writeln!(out);
    let _ = writeln!(out, "///|");
    let _ = writeln!(
        out,
        "/// `tools/oracle` の `demux-cases` が返すケース表（生成物）。"
    );
    let _ = writeln!(out, "///");
    let _ = writeln!(
        out,
        "/// 型は `src/demux/mp4_file_demux_oracle_test.mbt` で定義する。手で編集しない。"
    );
    let _ = writeln!(out, "let oracle_demux_cases : Array[OracleDemuxCase] = [");

    let video_audio = muxed_video_audio();
    for case in &demux_cases(&video_audio) {
        let outcome = drive_demux_case(case);
        let _ = writeln!(out, "  {{");
        let _ = writeln!(out, "    name: {},", moonbit_string(&case.name));
        let _ = writeln!(out, "    input: {},", moonbit_bytes_chunked(&case.input));
        let request_strs: Vec<String> = outcome
            .requests
            .iter()
            .map(|(position, size)| match size {
                Some(size) => format!("{{ position: {position}, size: Some({size}) }}"),
                None => format!("{{ position: {position}, size: None }}"),
            })
            .collect();
        let _ = writeln!(out, "    requests: [{}],", request_strs.join(", "));
        let tracks: Vec<String> = outcome
            .tracks
            .iter()
            .map(|line| moonbit_string(line))
            .collect();
        let _ = writeln!(out, "    tracks: [{}],", tracks.join(", "));
        let _ = writeln!(
            out,
            "    tracks_error: {},",
            moonbit_string(&outcome.tracks_error)
        );
        let _ = writeln!(out, "    samples: [");
        for line in &outcome.samples {
            let _ = writeln!(out, "      {},", moonbit_string(line));
        }
        let _ = writeln!(out, "    ],");
        let _ = writeln!(
            out,
            "    samples_error: {},",
            moonbit_string(&outcome.samples_error)
        );
        let _ = writeln!(out, "    prev_samples: [");
        for line in &outcome.prev_samples {
            let _ = writeln!(out, "      {},", moonbit_string(line));
        }
        let _ = writeln!(out, "    ],");
        let _ = writeln!(
            out,
            "    prev_error: {},",
            moonbit_string(&outcome.prev_error)
        );
        let _ = writeln!(out, "    seek_probes: [");
        for (secs, nanos, expected) in &outcome.seek_results {
            let _ = writeln!(
                out,
                "      {{ secs: {secs}, nanos: {nanos}U, expected: {} }},",
                moonbit_string(expected)
            );
        }
        let _ = writeln!(out, "    ],");
        let _ = writeln!(out, "  }},");
    }
    let _ = writeln!(out, "]");
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sample_entry_cases_output_is_deterministic_and_covers_variants() {
        let json = run_sample_entry_cases();
        assert_eq!(json, run_sample_entry_cases());
        // 全 variant が観測できる
        for variant in [
            "avc1", "hev1", "hvc1", "vp08", "vp09", "av01", "Opus", "mp4a", "fLaC",
            "unknown",
        ] {
            assert!(
                json.contains(&format!("\"variant={variant}\"")),
                "missing variant {variant}"
            );
        }
        // 必須子ボックス欠落は invalid_data
        assert!(json.contains("Missing mandatory 'avcc' box in 'avc1' box"));
        assert!(json.contains("Missing mandatory 'esds' box in 'mp4a' box"));
        // バージョン検証
        assert!(json.contains("Unsupported avcC configuration version: 2"));
        assert!(json.contains("Unsupported hvcC version: 2"));
        assert!(json.contains("Unsupported dOps version: 1"));
        assert!(json.contains("Unsupported av1C version: 2"));
        assert!(json.contains("Unsupported dfLa version: 1"));
        // デコード成功だが再エンコード失敗（profile 100 + 末尾省略 avcC）
        assert!(json.contains("\"name\": \"avc1_profile100_no_tail\""));
        assert!(json.contains("Missing 'chroma_format' field in 'avcC' box"));
        // data_reference_index=0 は NonZeroU16 の invalid_input
        assert!(json.contains("Expected a non-zero integer, but got 0"));
    }

    #[test]
    fn sample_entry_cases_cover_every_error_kind() {
        let json = run_sample_entry_cases();
        for kind in [
            "invalid_input",
            "invalid_data",
            "insufficient_buffer",
            "unsupported",
        ] {
            assert!(
                json.contains(kind),
                "missing error kind {kind}"
            );
        }
    }

    #[test]
    fn sample_entry_moonbit_output_is_deterministic() {
        assert_eq!(sample_entry_moonbit_cases(), sample_entry_moonbit_cases());
        assert_eq!(
            sample_entry_moonbit_fixtures(),
            sample_entry_moonbit_fixtures()
        );
    }

    #[test]
    fn sample_entry_fixture_entries_round_trip() {
        let fixtures = sample_entry_fixture_entries();
        assert!(fixtures.len() >= 9, "expected entries from all fixtures");
        for (name, track_index, entry_index, bytes) in &fixtures {
            let (entry, _) = SampleEntry::decode(bytes).unwrap_or_else(|e| {
                panic!(
                    "{name} track {track_index} entry {entry_index}: decode failed: {}: {}",
                    error_kind_str(e.kind),
                    e.reason
                )
            });
            assert!(!entry.is_unknown_box() || name.contains("unknown"));
        }
    }

    #[test]
    fn box_headers_output_is_deterministic_and_covers_boundaries() {
        let json = run_box_headers();
        assert_eq!(json, run_box_headers());
        // size=0 のトップレベルは末尾までをペイロードにする
        assert!(json.contains(
            "\"name\": \"size0_tail\", \"input\": \"000000006d646174aabbcc\", \"ok\": true"
        ));
        // size がヘッダー長未満は invalid_input
        assert!(json.contains("\"name\": \"size4_too_small\""));
        assert!(json.contains("\"name\": \"size4_too_small\", \"input\": \"000000046d646174\", \"ok\": false, \"error_kind\": \"invalid_input\""));
        // largesize=0 は可変長として扱わず invalid_data
        assert!(json.contains("\"name\": \"largesize0\""));
        assert!(json.contains("\"name\": \"largesize0\", \"input\": \"000000016d6461740000000000000000\", \"ok\": false, \"error_kind\": \"invalid_data\""));
        // バッファ不足は insufficient_buffer
        assert!(json.contains("\"name\": \"size16_truncated\""));
        assert!(json.contains("\"name\": \"size16_truncated\", \"input\": \"000000106d646174aabb\", \"ok\": false, \"error_kind\": \"insufficient_buffer\""));
        // uuid と largesize を含むケースが u64 総長として通る
        assert!(json.contains("\"name\": \"uuid_largesize40\""));
        assert!(json.contains(
            "\"size_kind\": \"u64\", \"size\": \"40\", \"external_size\": 32, \"payload_size\": 8"
        ));
    }

    #[test]
    fn box_tree_cases_output_is_deterministic_and_covers_boundaries() {
        let json = run_box_tree_cases();
        assert_eq!(json, run_box_tree_cases());
        // トップレベル size==0 は末尾までを 1 ノードとして受理する
        assert!(json.contains(
            "\"name\": \"unknown_top_level_size0\", \"input\": \"000000007a7a7a7aaabb\", \"ok\": true"
        ));
        // 入れ子 size==0 は invalid_data
        assert!(json.contains("\"name\": \"unknown_nested_size0\", \"input\": \"000000106d6f6f76000000007a7a7a7a\", \"ok\": false, \"error_kind\": \"invalid_data\""));
        // 親境界を超える子は insufficient_buffer
        assert!(json.contains("\"name\": \"child_exceeds_parent\", \"input\": \"000000106d6f6f760000000c7a7a7a7a\", \"ok\": false, \"error_kind\": \"insufficient_buffer\""));
        // ヘッダー未満の子サイズは invalid_input
        assert!(json.contains("\"name\": \"child_declared_size_below_header\", \"input\": \"000000106d6f6f76000000047a7a7a7a\", \"ok\": false, \"error_kind\": \"invalid_input\""));
        // 深さ上限は unsupported
        assert!(json.contains("\"name\": \"nested_beyond_depth_limit\""));
        assert!(json.contains("\"name\": \"nested_beyond_depth_limit\", \"input\": \""));
        // 入れ子 (moov > trak > mdia) は 3 レベルとして観測する
        assert!(json.contains(
            "\"name\": \"moov_trak_mdia_nesting\", \"input\": \"000000186d6f6f76000000107472616b000000086d646961\", \"ok\": true"
        ));
        assert!(json.contains("\"depth\": 3, \"type\": \"mdia\""));
        // free の payload は子として解釈しない (depth 2 の zzzz が現れない)
        let free_case = json
            .split("\"name\": \"free_payload_not_interpreted\"")
            .nth(1)
            .expect("case present");
        assert!(!free_case[..free_case.find("\"name\": \"").unwrap_or(free_case.len())]
            .contains("\"depth\": 2"));
    }

    #[test]
    fn box_tree_cases_cover_every_outcome_kind() {
        let json = run_box_tree_cases();
        for kind in [
            "invalid_input",
            "invalid_data",
            "insufficient_buffer",
            "unsupported",
        ] {
            assert!(
                json.contains(&format!("\"error_kind\": \"{kind}\"")),
                "missing error kind {kind}"
            );
        }
    }

    #[test]
    fn box_tree_moonbit_output_is_deterministic() {
        assert_eq!(box_tree_moonbit_cases(), box_tree_moonbit_cases());
        assert_eq!(box_tree_moonbit_fixtures(), box_tree_moonbit_fixtures());
    }

    #[test]
    fn box_tree_fixture_trees_are_walkable() {
        for (name, data) in BOX_TREE_FIXTURES {
            match walk_box_tree(data) {
                BoxTreeOutcome::Ok(nodes) => {
                    assert!(!nodes.is_empty(), "{name} has no boxes");
                    assert_eq!(nodes[0].depth, 1);
                    assert_eq!(&nodes[0].box_type, b"ftyp", "{name} does not start with ftyp");
                    let (ftyp, _) =
                        shiguredo_mp4::boxes::FtypBox::decode(data).expect("ftyp decode");
                    assert_eq!(ftyp.major_brand.get(), *b"isom");
                }
                BoxTreeOutcome::Err(kind) => panic!("{name} walk failed: {kind}"),
            }
        }
    }

    #[test]
    fn moov_tree_cases_output_is_deterministic_and_covers_boundaries() {
        let json = run_moov_tree_cases();
        assert_eq!(json, run_moov_tree_cases());
        assert!(json.contains("\"name\": \"minimal_v0\", \"input\": \""));
        // v1 の 64-bit 値は decimal string で現れる
        assert!(json.contains("moov.mvhd.creation_time=4294967296"));
        // 必須ボックスの欠落は invalid_data + 固定理由
        assert!(json.contains("Missing mandatory 'mvhd' box in 'moov' box"));
        assert!(json.contains("Missing mandatory 'dref' box in 'dinf' box"));
        // timescale=0 は NonZeroU32 の decode エラー
        assert!(json.contains("Expected a non-zero integer, but got 0"));
        // NUL 終端なし・不正 UTF-8
        assert!(json.contains("Null-terminated string not found"));
        assert!(json.contains("Invalid UTF-8 string: [255, 254]"));
        // 子の途中終端は insufficient_buffer
        assert!(json.contains("\"name\": \"truncated_child\""));
        assert!(json.contains("insufficient_buffer"));
        // duplicate は最初の値が勝つ
        let dup = json
            .split("\"name\": \"duplicate_mvhd\"")
            .nth(1)
            .expect("duplicate_mvhd case");
        let dup = &dup[..dup.find("\"name\": \"").unwrap_or(dup.len())];
        assert!(dup.contains("moov.mvhd.duration=2000"));
        assert!(!dup.contains("moov.mvhd.duration=3000"));
    }

    #[test]
    fn moov_tree_cases_cover_success_and_error_kinds() {
        let json = run_moov_tree_cases();
        for name in [
            "minimal_v0",
            "minimal_v1",
            "zero_tracks_unknown_extras",
            "video_track_vmhd",
            "audio_track_smhd",
            "subtitle_track_sthd",
            "text_track_nmhd",
            "two_tracks_mixed_versions",
            "duplicate_mvhd",
        ] {
            assert!(
                json.contains(&format!("\"name\": \"{name}\"")),
                "missing case {name}"
            );
        }
        for kind in ["invalid_input", "invalid_data", "insufficient_buffer"] {
            assert!(
                json.contains(&format!("\"error_kind\": \"{kind}\"")),
                "missing error kind {kind}"
            );
        }
    }

    #[test]
    fn moov_tree_moonbit_output_is_deterministic() {
        assert_eq!(moov_tree_moonbit_cases(), moov_tree_moonbit_cases());
        assert_eq!(moov_tree_moonbit_fixtures(), moov_tree_moonbit_fixtures());
    }

    #[test]
    fn moov_tree_fixture_moovs_are_decodable() {
        for (name, moov) in moov_tree_fixture_moovs() {
            let (decoded, used) = MoovBox::decode(&moov).unwrap_or_else(|e| {
                panic!(
                    "{name}: moov decode failed: {}: {}",
                    error_kind_str(e.kind),
                    e.reason
                )
            });
            assert_eq!(used, moov.len(), "{name}: moov decode length");
            assert!(!decoded.trak_boxes.is_empty(), "{name}: no tracks");
            let snapshot = moov_snapshot(&decoded);
            assert!(
                snapshot[0].starts_with("moov.mvhd.creation_time="),
                "{name}: first line"
            );
            assert!(
                snapshot.iter().any(|l| l == "moov.trak_count=1"),
                "{name}: track count"
            );
            assert!(
                snapshot
                    .iter()
                    .any(|l| l == "trak[0].mdia.hdlr.handler_type=vide"),
                "{name}: video handler"
            );
        }
    }

    #[test]
    fn moov_tree_file_output_is_deterministic() {
        let path = "../../tests/fixtures/upstream/black-h264-fmp4.mp4";
        let json = run_moov_tree(path).expect("run_moov_tree");
        assert_eq!(json, run_moov_tree(path).expect("run_moov_tree"));
        assert!(json.contains("\"status\": \"ok\""));
        assert!(json.contains("\"moov_tree\""));
    }

    #[test]
    fn extract_top_level_box_reports_missing_box() {
        let error = extract_top_level_box(b"\x00\x00\x00\x08free", b"moov").unwrap_err();
        assert_eq!(error.0, "invalid_data");
        assert_eq!(error.1, "moov box not found");
    }

    #[test]
    fn sha256_known_vectors() {
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn json_string_escaping() {
        assert_eq!(json_string_to("a\"b\\c\n"), "\"a\\\"b\\\\c\\n\"");
        assert_eq!(json_string_to("avc1"), "\"avc1\"");
    }

    #[test]
    fn sample_table_cases_output_is_deterministic_and_covers_boundaries() {
        let json = run_sample_table_cases();
        assert_eq!(json, run_sample_table_cases());
        // fixed / variable stsz, exact data offsets
        assert!(json.contains("\"name\": \"single_sample_fixed\""));
        assert!(json.contains("sample[0].data_offset=1000"));
        assert!(json.contains("sample[0].data_size=10"));
        assert!(json.contains("sample[0].cto=none"));
        // `ctts` なしと 0 / 負値 / u32::MAX の区別
        assert!(json.contains("sample[0].cto=0"));
        assert!(json.contains("sample[0].cto=-100"));
        assert!(json.contains("sample[1].cto=4294967295"));
        // co64 の 64bit offset と stco の u32::MAX
        assert!(json.contains("sample[0].data_offset=4294967296"));
        assert!(json.contains("sample[0].data_offset=4294967295"));
        // u32 を超える累計尺は 64bit の十進で現れる
        assert!(json.contains("sample[2].timestamp=4000000000"));
        // stss present (partial) / missing / empty
        assert!(json.contains("sample[1].sync=false"));
        assert!(json.contains("\"name\": \"stss_missing_all_sync\""));
        assert!(json.contains("\"name\": \"stss_empty_none_sync\""));
        // accessor error lines
        assert!(json.contains("\"error=accessor\""));
        assert!(json.contains("\"error.variant=InconsistentSampleCount\""));
        assert!(json.contains("\"other_box_type=stsz\""));
        assert!(json.contains("\"error.variant=SampleDataOffsetOverflow\""));
        assert!(json.contains("accumulated_offset=18446744073709551610"));
        // decode errors: exact upstream reasons
        assert!(json.contains("Missing mandatory 'stsd' box in 'stbl' box"));
        assert!(json.contains("Missing mandatory 'stco' or 'co64' box in 'stbl' box"));
        assert!(json.contains("Invalid ctts box version: 2"));
        assert!(json.contains("Invalid cslg box version: 2"));
        assert!(json.contains("Invalid sdtp box version: 1"));
        assert!(json.contains("Expected a non-zero integer, but got 0"));
    }

    #[test]
    fn sample_table_cases_cover_every_accessor_error_variant() {
        let json = run_sample_table_cases();
        for variant in [
            "InconsistentSampleCount",
            "FirstChunkIndexIsNotOne",
            "LastChunkIndexIsTooLarge",
            "MissingSampleEntry",
            "ChunkIndicesNotMonotonicallyIncreasing",
            "ChunksExistButNoSamples",
            "SampleCountOverflow",
            "SampleDataOffsetOverflow",
        ] {
            assert!(
                json.contains(&format!("\"error.variant={variant}\"")),
                "missing accessor error variant {variant}"
            );
        }
    }

    #[test]
    fn sample_table_cases_cover_decode_error_kinds() {
        let json = run_sample_table_cases();
        for kind in ["invalid_input", "invalid_data", "insufficient_buffer"] {
            assert!(
                json.contains(&format!("\"error_kind\": \"{kind}\"")),
                "missing error kind {kind}"
            );
        }
    }

    #[test]
    fn sample_table_moonbit_output_is_deterministic() {
        assert_eq!(sample_table_moonbit_cases(), sample_table_moonbit_cases());
        assert_eq!(
            sample_table_moonbit_fixtures(),
            sample_table_moonbit_fixtures()
        );
    }

    #[test]
    fn sample_table_fixture_stbls_decode_and_snapshot() {
        let stbls = sample_table_fixture_stbls();
        assert_eq!(stbls.len(), 9, "expected one track per fixture");
        for (name, track_index, stbl) in &stbls {
            match sample_table_outcome(stbl) {
                SampleTableOutcome::Ok(snapshot) => {
                    assert!(
                        !snapshot.is_empty(),
                        "{name} track {track_index}: empty snapshot"
                    );
                    assert!(
                        snapshot[0].starts_with("sample_count="),
                        "{name} track {track_index}: first line is {}",
                        snapshot[0]
                    );
                }
                SampleTableOutcome::DecodeErr { kind, reason } => {
                    panic!("{name} track {track_index}: stbl decode failed: {kind}: {reason}");
                }
            }
        }
    }

    #[test]
    fn sample_table_file_output_is_deterministic() {
        let path = "../../tests/fixtures/upstream/black-h264-video.mp4";
        let json = run_sample_tables(path).expect("run_sample_tables");
        assert_eq!(json, run_sample_tables(path).expect("run_sample_tables"));
        assert!(json.contains("\"sample_tables\""));
        assert!(json.contains("\"status\": \"ok\""));
        assert!(json.contains("\"moov_error\": null"));
    }
}
