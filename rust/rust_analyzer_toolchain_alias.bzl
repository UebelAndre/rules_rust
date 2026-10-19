"""# rust_analyzer_toolchain_alias.bzl"""

load(
    "//rust/private:rust_analyzer.bzl",
    _rust_analyzer_toolchain_alias = "rust_analyzer_toolchain_alias",
)

rust_analyzer_toolchain_alias = _rust_analyzer_toolchain_alias
