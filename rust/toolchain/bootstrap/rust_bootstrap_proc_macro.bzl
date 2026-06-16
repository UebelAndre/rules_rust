"""# rust_bootstrap_proc_macro

A variant of `rust_proc_macro` built with the bootstrap toolchain. Targets built
with this rule have access to the process wrapper but not the persistent worker,
making it suitable for building toolchain dependencies (like proc-macros used by
the persistent worker's vendored crates, e.g. `serde_derive`).
"""

load(
    "//rust/private:rust.bzl",
    _rust_bootstrap_proc_macro = "rust_bootstrap_proc_macro",
)

rust_bootstrap_proc_macro = _rust_bootstrap_proc_macro
