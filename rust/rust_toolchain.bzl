"""# Rust Toolchains

Public entry point for Rust toolchain rules. Implementation lives in
`//rust/private:toolchain.bzl`; this module re-exports the user-facing
symbols.
"""

load(
    "//rust/private:toolchain.bzl",
    _current_rust_analyzer_toolchain = "current_rust_analyzer_toolchain",
    _current_rustfmt_toolchain = "current_rustfmt_toolchain",
    _rust_analyzer_toolchain = "rust_analyzer_toolchain",
    _rust_stdlib_filegroup = "rust_stdlib_filegroup",
    _rust_toolchain = "rust_toolchain",
    _rustfmt_toolchain = "rustfmt_toolchain",
)

rust_toolchain = _rust_toolchain
rust_stdlib_filegroup = _rust_stdlib_filegroup
rust_analyzer_toolchain = _rust_analyzer_toolchain
current_rust_analyzer_toolchain = _current_rust_analyzer_toolchain
rustfmt_toolchain = _rustfmt_toolchain
current_rustfmt_toolchain = _current_rustfmt_toolchain
