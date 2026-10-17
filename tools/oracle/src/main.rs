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

use shiguredo_mp4::boxes::{MediaHeader, MoovBox};
use shiguredo_mp4::demux::{DemuxError, Input, Mp4FileDemuxer, Mp4FileKind, Mp4FileKindDetector};
use shiguredo_mp4::{
    BaseBox, BoxHeader, BoxSize, Decode, Encode, FixedPointNumber, LanguageCode, TrackKind,
};

/// Pinned upstream revision (must match Cargo.toml and docs/upstream.md).
const UPSTREAM_SHA: &str = "1282b704f44184ec792e1549b5d31e0c4c54dc59";

/// Golden schema version. Bump when the normalised shape changes.
const SCHEMA_VERSION: u32 = 1;

/// Safety cap for sample enumeration (guards against pathological inputs).
const MAX_SAMPLES: u64 = 10_000_000;

/// Upper bound on incremental input feeding steps.
const MAX_INPUT_STEPS: u64 = 10_000;

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

/// Runs the incremental file kind detector over the whole buffer.
fn kind_json(data: &[u8]) -> String {
    let mut detector = Mp4FileKindDetector::new();
    let mut steps = 0;
    while let Some(required) = detector.required_input() {
        steps += 1;
        if steps > MAX_INPUT_STEPS {
            return "{\"status\": \"error\", \"classification\": \"input_not_satisfied\", \"message\": \"input feeding did not terminate\"}".to_owned();
        }
        detector.handle_input(input_at(data, required.position));
    }
    match detector.file_kind() {
        Ok(Some(kind)) => {
            let value = match kind {
                Mp4FileKind::Mp4 => "mp4",
                Mp4FileKind::FragmentedMp4 => "fragmented-mp4",
            };
            format!("{{\"status\": \"ok\", \"value\": \"{value}\"}}")
        }
        Ok(None) => "{\"status\": \"unverified\", \"value\": null}".to_owned(),
        Err(e) => {
            format!(
                "{{\"status\": \"error\", \"error\": {}}}",
                demux_error_json(&e)
            )
        }
    }
}

/// Feeds the whole file to a fresh demuxer, mirroring the upstream example.
fn new_fed_demuxer(data: &[u8]) -> Result<Mp4FileDemuxer, String> {
    let mut demuxer = Mp4FileDemuxer::new();
    let mut steps = 0;
    while let Some(required) = demuxer.required_input() {
        steps += 1;
        if steps > MAX_INPUT_STEPS {
            return Err("input feeding did not terminate".to_owned());
        }
        demuxer.handle_input(input_at(data, required.position));
    }
    Ok(demuxer)
}

fn tracks_json(data: &[u8]) -> String {
    let mut demuxer = match new_fed_demuxer(data) {
        Ok(d) => d,
        Err(e) => {
            return format!(
                "{{\"status\": \"error\", \"classification\": \"input_not_satisfied\", \"message\": {}}}",
                json_string_to(&e)
            );
        }
    };
    match demuxer.tracks() {
        Ok(tracks) => {
            let tracks: Vec<(u32, TrackKind, u64, u32)> = tracks
                .iter()
                .map(|t| (t.track_id, t.kind, t.duration, t.timescale.get()))
                .collect();
            let mut items = String::new();
            for (i, (track_id, kind, duration, timescale)) in tracks.iter().enumerate() {
                if i > 0 {
                    items.push_str(", ");
                }
                let _ = write!(
                    items,
                    "{{\"track_id\": \"{track_id}\", \"kind\": \"{}\", \"timescale\": \"{timescale}\", \"duration\": \"{duration}\"}}",
                    track_kind_str(*kind)
                );
            }
            format!("{{\"status\": \"ok\", \"items\": [{items}]}}")
        }
        Err(e) => format!(
            "{{\"status\": \"error\", \"error\": {}}}",
            demux_error_json(&e)
        ),
    }
}

fn samples_json(data: &[u8]) -> String {
    let mut demuxer = match new_fed_demuxer(data) {
        Ok(d) => d,
        Err(e) => {
            return format!(
                "{{\"status\": \"error\", \"classification\": \"input_not_satisfied\", \"message\": {}}}",
                json_string_to(&e)
            );
        }
    };
    let mut items: Vec<String> = Vec::new();
    let mut index: u64 = 0;
    let mut truncated = false;
    let mut error: Option<DemuxError> = None;
    loop {
        match demuxer.next_sample() {
            Ok(Some(sample)) => {
                index += 1;
                if index > MAX_SAMPLES {
                    truncated = true;
                    break;
                }
                let entry = match sample.sample_entry {
                    Some(entry) => json_string_to(&entry.box_type().to_string()),
                    None => "null".to_owned(),
                };
                let pts = match sample.composition_time_offset {
                    Some(v) => format!("\"{v}\""),
                    None => "null".to_owned(),
                };
                items.push(format!(
                    "{{\"index\": \"{index}\", \"track_id\": \"{}\", \"sample_entry\": {entry}, \"keyframe\": {}, \"dts\": \"{}\", \"duration\": \"{}\", \"pts_offset\": {pts}, \"data_offset\": \"{}\", \"data_size\": \"{}\"}}",
                    sample.track.track_id,
                    sample.keyframe,
                    sample.timestamp,
                    sample.duration,
                    sample.data_offset,
                    sample.data_size,
                ));
            }
            Ok(None) => break,
            Err(e) => {
                error = Some(e);
                break;
            }
        }
    }
    let items = items.join(", ");
    match error {
        Some(e) => format!(
            "{{\"status\": \"error\", \"items\": [{items}], \"truncated\": {truncated}, \"error\": {}}}",
            demux_error_json(&e)
        ),
        None => format!(
            "{{\"status\": \"ok\", \"items\": [{items}], \"truncated\": {truncated}}}"
        ),
    }
}

/// Builds an `Input` covering `data[position..]`, mirroring a caller that has
/// the whole fixture in memory. An out-of-range position yields empty input.
fn input_at(data: &[u8], position: u64) -> Input<'_> {
    let start = usize::try_from(position).unwrap_or(usize::MAX);
    let slice = data.get(start..).unwrap_or(&[]);
    Input {
        position,
        data: slice,
    }
}

fn track_kind_str(kind: TrackKind) -> &'static str {
    match kind {
        TrackKind::Audio => "audio",
        TrackKind::Video => "video",
        TrackKind::Subtitle => "subtitle",
    }
}

fn demux_error_json(error: &DemuxError) -> String {
    match error {
        DemuxError::DecodeError(e) => format!(
            "{{\"classification\": \"decode_error\", \"error_kind\": \"{}\", \"box_type\": {}, \"message\": {}}}",
            error_kind_str(e.kind),
            match &e.box_type {
                Some(t) => json_string_to(&t.to_string()),
                None => "null".to_owned(),
            },
            json_string_to(&e.reason),
        ),
        DemuxError::SampleTableError(e) => format!(
            "{{\"classification\": \"sample_table_error\", \"message\": {}}}",
            json_string_to(&e.to_string())
        ),
        DemuxError::InvalidState(m) => format!(
            "{{\"classification\": \"invalid_state\", \"message\": {}}}",
            json_string_to(m)
        ),
        DemuxError::InputRequired(r) => format!(
            "{{\"classification\": \"input_required\", \"position\": \"{}\", \"size\": {}}}",
            r.position,
            match r.size {
                Some(s) => format!("\"{s}\""),
                None => "null".to_owned(),
            }
        ),
    }
}

fn error_kind_str(kind: shiguredo_mp4::ErrorKind) -> &'static str {
    use shiguredo_mp4::ErrorKind;
    match kind {
        ErrorKind::InvalidInput => "invalid_input",
        ErrorKind::InvalidData => "invalid_data",
        ErrorKind::InsufficientBuffer => "insufficient_buffer",
        ErrorKind::Unsupported => "unsupported",
    }
}

/// Emits a JSON string literal with escaping.
fn json_string(s: &str, out: &mut String) {
    out.push_str(&json_string_to(s));
}

fn json_string_to(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
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

/// Default maximum box-tree depth (top level is 1). Mirrors
/// `@bytes.DEFAULT_MAX_NESTING_DEPTH` and `@boxes.BoxTreeOptions::new`.
const DEFAULT_MAX_BOX_TREE_DEPTH: i32 = 64;

/// Default maximum total node count. Mirrors `@boxes.DEFAULT_MAX_BOX_TREE_NODES`.
const DEFAULT_MAX_BOX_TREE_NODES: i32 = 65_536;

/// Box types whose payload is a plain sequence of child boxes. Mirrors
/// `@boxes.is_plain_container_box_type` (`src/boxes/box_node.mbt`).
///
/// `stsd` / `meta` (prefix fields) and sample entries (children start after
/// fixed fields) are intentionally not included.
fn is_plain_container_box_type(box_type: &[u8]) -> bool {
    const CONTAINERS: &[&[u8]] = &[
        b"moov", b"trak", b"mdia", b"minf", b"stbl", b"edts", b"dinf", b"mvex", b"moof", b"traf",
        b"mfra", b"udta",
    ];
    CONTAINERS.contains(&box_type)
}

/// One node of the header-level box-tree walk (pre-order, flattened).
struct BoxTreeNode {
    depth: i32,
    box_type: Vec<u8>,
    start: u64,
    header_bytes: i32,
    declared_size: u64,
    total_size: u64,
}

/// Box-tree walk result shared by the JSON and MoonBit emitters.
enum BoxTreeOutcome {
    Ok(Vec<BoxTreeNode>),
    Err(&'static str),
}

/// Walks the whole buffer with the default limits.
fn walk_box_tree(data: &[u8]) -> BoxTreeOutcome {
    let mut nodes = Vec::new();
    let mut node_count = 0i32;
    match walk_box_tree_into(data, 0, 1, &mut node_count, &mut nodes) {
        Ok(()) => BoxTreeOutcome::Ok(nodes),
        Err(kind) => BoxTreeOutcome::Err(error_kind_str(kind)),
    }
}

/// Header-level walk mirroring `@boxes.build_box_tree`:
///
/// - `size==0` is only allowed at the top level (`invalid_data` otherwise);
/// - only plain containers are descended into (`unsupported` past the depth
///   limit, counted against the node budget);
/// - payload bytes are never retained, only their range.
fn walk_box_tree_into(
    data: &[u8],
    base: u64,
    depth: i32,
    node_count: &mut i32,
    out: &mut Vec<BoxTreeNode>,
) -> Result<(), shiguredo_mp4::ErrorKind> {
    use shiguredo_mp4::ErrorKind;

    let mut rest = data;
    let mut offset = base;
    while !rest.is_empty() {
        let (header, payload) = BoxHeader::decode_header_and_payload(rest).map_err(|e| e.kind)?;
        let header_bytes = header.external_size();
        let declared_size = header.box_size.get();
        let total_size = header_bytes as u64 + payload.len() as u64;
        let box_type = header.box_type.as_bytes().to_vec();
        if depth > 1 && declared_size == 0 {
            return Err(ErrorKind::InvalidData);
        }
        *node_count += 1;
        if *node_count > DEFAULT_MAX_BOX_TREE_NODES {
            return Err(ErrorKind::Unsupported);
        }
        out.push(BoxTreeNode {
            depth,
            box_type: box_type.clone(),
            start: offset,
            header_bytes: header_bytes as i32,
            declared_size,
            total_size,
        });
        if is_plain_container_box_type(&box_type) && !payload.is_empty() {
            if depth >= DEFAULT_MAX_BOX_TREE_DEPTH {
                return Err(ErrorKind::Unsupported);
            }
            walk_box_tree_into(
                payload,
                offset + header_bytes as u64,
                depth + 1,
                node_count,
                out,
            )?;
        }
        rest = &rest[total_size as usize..];
        offset += total_size;
    }
    Ok(())
}

/// `ftyp` fields decoded by the upstream `FtypBox` (null when absent/invalid).
fn ftyp_json(data: &[u8]) -> String {
    if data.len() < 8 || &data[4..8] != b"ftyp" {
        return "null".to_owned();
    }
    match shiguredo_mp4::boxes::FtypBox::decode(data) {
        Ok((ftyp, _)) => {
            let major = ftyp.major_brand.get();
            let brands: Vec<String> = ftyp
                .compatible_brands
                .iter()
                .map(|b| json_string_to(&fourcc_display(b.get())))
                .collect();
            format!(
                "{{\"major_brand\": {}, \"major_brand_hex\": \"{}\", \"minor_version\": \"{}\", \"compatible_brands\": [{}]}}",
                json_string_to(&fourcc_display(major)),
                hex(&major),
                ftyp.minor_version,
                brands.join(", "),
            )
        }
        Err(_) => "null".to_owned(),
    }
}

/// Renders a 4-byte code as a string when it is printable ASCII, hex otherwise.
fn fourcc_display(code: [u8; 4]) -> String {
    if code.iter().all(|b| (0x20..=0x7e).contains(b)) {
        String::from_utf8_lossy(&code).into_owned()
    } else {
        hex(&code)
    }
}

fn box_tree_node_json(node: &BoxTreeNode) -> String {
    format!(
        "{{\"depth\": {}, \"type\": {}, \"type_hex\": \"{}\", \"start\": \"{}\", \"header_bytes\": {}, \"declared_size\": \"{}\", \"total_size\": \"{}\"}}",
        node.depth,
        json_string_to(&String::from_utf8_lossy(&node.box_type)),
        hex(&node.box_type),
        node.start,
        node.header_bytes,
        node.declared_size,
        node.total_size,
    )
}

fn box_tree_nodes_json(nodes: &[BoxTreeNode]) -> String {
    let items: Vec<String> = nodes.iter().map(box_tree_node_json).collect();
    format!("[{}]", items.join(", "))
}

fn box_tree_json(data: &[u8]) -> String {
    let tree = match walk_box_tree(data) {
        BoxTreeOutcome::Ok(nodes) => format!(
            "{{\"status\": \"ok\", \"nodes\": {}}}",
            box_tree_nodes_json(&nodes)
        ),
        BoxTreeOutcome::Err(kind) => {
            format!("{{\"status\": \"error\", \"error_kind\": \"{kind}\"}}")
        }
    };
    format!("{{\"ftyp\": {}, \"tree\": {tree}}}", ftyp_json(data))
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

fn hex(data: &[u8]) -> String {
    let mut out = String::with_capacity(data.len() * 2);
    for byte in data {
        let _ = write!(out, "{byte:02x}");
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
