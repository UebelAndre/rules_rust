"""Bazel rules for [wasm-bindgen](https://crates.io/crates/wasm-bindgen)"""

load(
    "//wasm_bindgen:providers.bzl",
    _RustWasmBindgenInfo = "RustWasmBindgenInfo",
)
load(
    "//wasm_bindgen/private:wasm_bindgen.bzl",
    _rust_wasm_bindgen = "rust_wasm_bindgen",
    _rust_wasm_bindgen_toolchain = "rust_wasm_bindgen_toolchain",
)
load(
    "//wasm_bindgen/private:wasm_bindgen_test.bzl",
    _rust_wasm_bindgen_test = "rust_wasm_bindgen_test",
)

rust_wasm_bindgen = _rust_wasm_bindgen
rust_wasm_bindgen_test = _rust_wasm_bindgen_test
rust_wasm_bindgen_toolchain = _rust_wasm_bindgen_toolchain
RustWasmBindgenInfo = _RustWasmBindgenInfo
