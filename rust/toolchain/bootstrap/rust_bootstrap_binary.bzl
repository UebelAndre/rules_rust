"""# rust_bootstrap_binary

A variant of `rust_binary` built with the bootstrap toolchain. Targets built
with this rule have access to the process wrapper but not the persistent worker,
making it suitable for building toolchain dependencies (like the persistent
worker itself and its vendored crates).
"""

load(
    "//rust/private:rust.bzl",
    _rust_bootstrap_binary = "rust_bootstrap_binary",
)

rust_bootstrap_binary = _rust_bootstrap_binary
