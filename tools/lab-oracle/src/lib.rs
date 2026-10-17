//! Rust/WASM reference side of the browser diff lab (issue 0016).
//!
//! Compiled to `wasm32-unknown-unknown` as a raw `cdylib` with the same
//! pointer/Vec ABI shape as upstream `examples/dump_wasm`: the caller copies
//! input bytes into wasm memory, calls `oracle_dump`, and reads back a
//! canonical-schema JSON string (kind + tracks + samples + box tree) produced
//! by the very emitters that generate `tests/fixtures/golden/*.json`.
//!
//! No wasm-bindgen and no DOM: the JS side only needs `WebAssembly.instantiate`
//! and manual pointer plumbing.

// Shares the golden emitters with tools/oracle (single source of truth for the
// normalised schema — a drift between them is exactly what CI must catch).
// Some helpers are used only by the bin; allow dead code for the cdylib build.
#[allow(dead_code)]
#[path = "../../oracle/src/oracle_json.rs"]
mod oracle_json;

/// Allocates `size` bytes in wasm linear memory. Free with `lab_free`.
///
/// Mirrors upstream `mp4_alloc` / `allocate_vec` conventions.
#[no_mangle]
pub extern "C" fn lab_alloc(size: u32) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let layout = std::alloc::Layout::from_size_align(size as usize, 1)
        .expect("layout creation with alignment 1 should never fail");
    let allocated = unsafe { std::alloc::alloc(layout) };
    if allocated.is_null() {
        std::alloc::handle_alloc_error(layout);
    }
    allocated
}

/// Frees a pointer returned by `lab_alloc`. Null/zero-size calls are no-ops.
#[no_mangle]
pub unsafe extern "C" fn lab_free(ptr: *mut u8, size: u32) {
    if ptr.is_null() || size == 0 {
        return;
    }
    let layout = std::alloc::Layout::from_size_align_unchecked(size as usize, 1);
    unsafe { std::alloc::dealloc(ptr, layout) };
}

/// `Vec<u8>` data pointer (null on null input).
#[no_mangle]
pub unsafe extern "C" fn lab_vec_ptr(v: *const Vec<u8>) -> *const u8 {
    if v.is_null() {
        return std::ptr::null();
    }
    unsafe { (*v).as_ptr() }
}

/// `Vec<u8>` length (0 on null input).
#[no_mangle]
pub unsafe extern "C" fn lab_vec_len(v: *const Vec<u8>) -> u32 {
    if v.is_null() {
        return 0;
    }
    unsafe { (*v).len() as u32 }
}

/// Frees a `Vec<u8>` previously returned by `oracle_dump`.
#[no_mangle]
pub unsafe extern "C" fn lab_vec_free(v: *mut Vec<u8>) {
    if !v.is_null() {
        drop(unsafe { Box::from_raw(v) });
    }
}

/// Runs the pinned-upstream reference demuxer over `bytes[..len]` and returns
/// a `Vec<u8>` holding the canonical JSON observation (schema_version 1
/// fields: `kind`, `tracks`, `samples`, plus `box_tree`). Never fails — decode
/// errors are reported inside the JSON `status`/`error` fields.
#[no_mangle]
pub extern "C" fn oracle_dump(bytes: *const u8, len: u32) -> *mut Vec<u8> {
    let data = if bytes.is_null() || len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(bytes, len as usize) }
    };
    let json = oracle_json::lab_report_json(data);
    Box::into_raw(Box::new(json.into_bytes()))
}
