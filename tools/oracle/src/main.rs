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

use shiguredo_mp4::demux::{DemuxError, Input, Mp4FileDemuxer, Mp4FileKind, Mp4FileKindDetector};
use shiguredo_mp4::{BaseBox, BoxHeader, BoxSize, Encode, TrackKind};

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
        _ => {
            eprintln!("usage: mp4-oracle demux <mp4-file>");
            eprintln!("       mp4-oracle box-headers");
            eprintln!("       mp4-oracle box-headers --moonbit");
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
