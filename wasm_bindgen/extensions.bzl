"""Module extensions for rules_rust/wasm_bindgen."""

load("//wasm_bindgen:repositories.bzl", "rust_wasm_bindgen_repositories")

def _toolchains_impl(_ctx):
    rust_wasm_bindgen_repositories()

toolchains = module_extension(implementation = _toolchains_impl)
