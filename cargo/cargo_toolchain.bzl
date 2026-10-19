"""# cargo_toolchain.bzl"""

load(
    "//cargo/private:cargo_toolchain.bzl",
    _cargo_toolchain = "cargo_toolchain",
    _cargo_toolchain_alias = "cargo_toolchain_alias",
    _find_cargo = "find_cargo",
)

cargo_toolchain = _cargo_toolchain
cargo_toolchain_alias = _cargo_toolchain_alias
find_cargo = _find_cargo
