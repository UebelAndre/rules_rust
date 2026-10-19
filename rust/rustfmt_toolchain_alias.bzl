"""# rustfmt_toolchain_alias.bzl"""

load(
    "//rust/private:rustfmt.bzl",
    _rustfmt_toolchain_alias = "rustfmt_toolchain_alias",
)

rustfmt_toolchain_alias = _rustfmt_toolchain_alias
