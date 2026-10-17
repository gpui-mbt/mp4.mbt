// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html

name = "gpui-mbt/mp4"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/gpui-mbt/mp4.mbt"

license = "Apache-2.0"

keywords = [ "mp4", "isobmff", "sans-io", "mux", "demux" ]

description = "Dependency-free, Sans I/O MP4/ISOBMFF mux/demux library (MoonBit port of shiguredo/mp4-rs)"

source = "src"

preferred_target = "js"

import {
  "moonbitlang/async@0.22.5",
}
