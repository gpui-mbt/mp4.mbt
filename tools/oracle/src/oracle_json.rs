//! JSON emit helpers shared by the `mp4-oracle` binary and the lab-oracle
//! wasm cdylib (issue 0016). Everything here is pure over `&[u8]` so it can be
//! `#[path]`-included into a `wasm32-unknown-unknown` crate: no fs/env/clock.

use std::fmt::Write as _;

use shiguredo_mp4::demux::{
    DemuxError, Input, Mp4FileDemuxer, Mp4FileKind, Mp4FileKindDetector,
};
use shiguredo_mp4::{BaseBox as _, BoxHeader, Decode as _, TrackKind};

/// Safety cap for sample enumeration (guards against pathological inputs).
pub(crate) const MAX_SAMPLES: u64 = 10_000_000;

/// Upper bound on incremental input feeding steps.
pub(crate) const MAX_INPUT_STEPS: u64 = 10_000;

/// Runs the incremental file kind detector over the whole buffer.
pub(crate) fn kind_json(data: &[u8]) -> String {
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
pub(crate) fn new_fed_demuxer(data: &[u8]) -> Result<Mp4FileDemuxer, String> {
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

pub(crate) fn tracks_json(data: &[u8]) -> String {
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

pub(crate) fn samples_json(data: &[u8]) -> String {
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
pub(crate) fn input_at(data: &[u8], position: u64) -> Input<'_> {
    let start = usize::try_from(position).unwrap_or(usize::MAX);
    let slice = data.get(start..).unwrap_or(&[]);
    Input {
        position,
        data: slice,
    }
}

pub(crate) fn track_kind_str(kind: TrackKind) -> &'static str {
    match kind {
        TrackKind::Audio => "audio",
        TrackKind::Video => "video",
        TrackKind::Subtitle => "subtitle",
    }
}

pub(crate) fn demux_error_json(error: &DemuxError) -> String {
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

pub(crate) fn error_kind_str(kind: shiguredo_mp4::ErrorKind) -> &'static str {
    use shiguredo_mp4::ErrorKind;
    match kind {
        ErrorKind::InvalidInput => "invalid_input",
        ErrorKind::InvalidData => "invalid_data",
        ErrorKind::InsufficientBuffer => "insufficient_buffer",
        ErrorKind::Unsupported => "unsupported",
    }
}

/// Emits a JSON string literal with escaping.
pub(crate) fn json_string(s: &str, out: &mut String) {
    out.push_str(&json_string_to(s));
}

pub(crate) fn json_string_to(s: &str) -> String {
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

/// Default maximum box-tree depth (top level is 1). Mirrors
/// `@bytes.DEFAULT_MAX_NESTING_DEPTH` and `@boxes.BoxTreeOptions::new`.
pub(crate) const DEFAULT_MAX_BOX_TREE_DEPTH: i32 = 64;

/// Default maximum total node count. Mirrors `@boxes.DEFAULT_MAX_BOX_TREE_NODES`.
pub(crate) const DEFAULT_MAX_BOX_TREE_NODES: i32 = 65_536;

/// Box types whose payload is a plain sequence of child boxes. Mirrors
/// `@boxes.is_plain_container_box_type` (`src/boxes/box_node.mbt`).
///
/// `stsd` / `meta` (prefix fields) and sample entries (children start after
/// fixed fields) are intentionally not included.
pub(crate) fn is_plain_container_box_type(box_type: &[u8]) -> bool {
    const CONTAINERS: &[&[u8]] = &[
        b"moov", b"trak", b"mdia", b"minf", b"stbl", b"edts", b"dinf", b"mvex", b"moof", b"traf",
        b"mfra", b"udta",
    ];
    CONTAINERS.contains(&box_type)
}

/// One node of the header-level box-tree walk (pre-order, flattened).
pub(crate) struct BoxTreeNode {
    pub(crate) depth: i32,
    pub(crate) box_type: Vec<u8>,
    pub(crate) start: u64,
    pub(crate) header_bytes: i32,
    pub(crate) declared_size: u64,
    pub(crate) total_size: u64,
}

/// Box-tree walk result shared by the JSON and MoonBit emitters.
pub(crate) enum BoxTreeOutcome {
    Ok(Vec<BoxTreeNode>),
    Err(&'static str),
}

/// Walks the whole buffer with the default limits.
pub(crate) fn walk_box_tree(data: &[u8]) -> BoxTreeOutcome {
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
pub(crate) fn walk_box_tree_into(
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
pub(crate) fn ftyp_json(data: &[u8]) -> String {
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
pub(crate) fn fourcc_display(code: [u8; 4]) -> String {
    if code.iter().all(|b| (0x20..=0x7e).contains(b)) {
        String::from_utf8_lossy(&code).into_owned()
    } else {
        hex(&code)
    }
}

pub(crate) fn box_tree_node_json(node: &BoxTreeNode) -> String {
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

pub(crate) fn box_tree_nodes_json(nodes: &[BoxTreeNode]) -> String {
    let items: Vec<String> = nodes.iter().map(box_tree_node_json).collect();
    format!("[{}]", items.join(", "))
}

pub(crate) fn box_tree_json(data: &[u8]) -> String {
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

pub(crate) fn hex(data: &[u8]) -> String {
    let mut out = String::with_capacity(data.len() * 2);
    for byte in data {
        let _ = write!(out, "{byte:02x}");
    }
    out
}

/// Reference observation for the browser diff lab (issue 0016): kind +
/// tracks + samples + box tree, using the exact same emitters as the
/// `demux`/`box-tree` golden modes so the lab oracle cannot drift.
// Consumed by tools/lab-oracle (wasm cdylib) via #[path] include, not by the bin.
#[allow(dead_code)]
pub fn lab_report_json(data: &[u8]) -> String {
    format!(
        "{{\"kind\": {}, \"tracks\": {}, \"samples\": {}, \"box_tree\": {}}}",
        kind_json(data),
        tracks_json(data),
        samples_json(data),
        box_tree_json(data),
    )
}
