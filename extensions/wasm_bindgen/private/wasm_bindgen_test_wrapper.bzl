"""wasm_bindgen_test_wrapper"""

load(
    ":wasm_bindgen_test.bzl",
    "rust_wasm_bindgen_test_binary",
    _rust_wasm_bindgen_test = "rust_wasm_bindgen_test",
)

def rust_wasm_bindgen_test(
        *,
        name,
        aliases = {},
        compile_data = [],
        crate_features = [],
        data = [],
        edition = None,
        env = {},
        env_inherit = [],
        proc_macro_deps = [],
        rustc_env = {},
        rustc_env_files = [],
        rustc_flags = [],
        target_arch = None,
        version = "0.0.0",
        wasm = None,
        tags = [],
        **kwargs):
    # Create a test binary for the
    rust_wasm_bindgen_test_binary(
        name = name + ".bin",
        aliases = aliases,
        compile_data = compile_data,
        crate_features = crate_features,
        data = data,
        edition = edition,
        env = env,
        env_inherit = env_inherit,
        proc_macro_deps = proc_macro_deps,
        rustc_env = rustc_env,
        rustc_env_files = rustc_env_files,
        rustc_flags = rustc_flags,
        target_arch = target_arch,
        version = version,
        wasm = wasm,
        tags = depset(tags + ["manual"]).to_list(),
        **kwargs
    )

    _rust_wasm_bindgen_test(
        name = name,
        wasm = name + ".bin",
        tags = tags,
        env = env,
        **kwargs
    )
