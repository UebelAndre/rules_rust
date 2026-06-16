"""# rust_bootstrap_library

A variant of `rust_library` built with the bootstrap toolchain. Targets built
with this rule have access to the process wrapper but not the persistent worker,
making it suitable for building toolchain dependencies (like the persistent
worker itself and its vendored crates).
"""

load(
    "//rust/private:rust.bzl",
    _rust_bootstrap_library = "rust_bootstrap_library",
)

rust_bootstrap_library = _rust_bootstrap_library
