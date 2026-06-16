"""# Bootstrap toolchain rules

Public entry point for `rust_bootstrap_*` rules. These rules build against the
bootstrap toolchain (`//rust/toolchain/bootstrap:toolchain_bootstrap_type`),
which has access to the process wrapper but not the persistent worker. Use
these rules to build targets that themselves are dependencies of
`rust_toolchain` (for example, the persistent worker binary and its
vendored crates).
"""

load(
    ":rust_bootstrap_binary.bzl",
    _rust_bootstrap_binary = "rust_bootstrap_binary",
)
load(
    ":rust_bootstrap_library.bzl",
    _rust_bootstrap_library = "rust_bootstrap_library",
)
load(
    ":rust_bootstrap_proc_macro.bzl",
    _rust_bootstrap_proc_macro = "rust_bootstrap_proc_macro",
)

rust_bootstrap_binary = _rust_bootstrap_binary
rust_bootstrap_library = _rust_bootstrap_library
rust_bootstrap_proc_macro = _rust_bootstrap_proc_macro
