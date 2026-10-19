"""# rust_toolchain_alias.bzl"""

load(
    "//rust/private:toolchain_utils.bzl",
    _rust_toolchain_alias = "rust_toolchain_alias",
)

rust_toolchain_alias = _rust_toolchain_alias
