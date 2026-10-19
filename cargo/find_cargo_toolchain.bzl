"""# find_cargo_toolchain.bzl

Helpers for rules which run Cargo through `@rules_rust//cargo:toolchain_type`,
after `find_cc_toolchain.bzl` from rules_cc.
"""

load(
    "//cargo/private:cargo_toolchain.bzl",
    _find_cargo = "find_cargo",
    _find_cargo_toolchain = "find_cargo_toolchain",
    _use_cargo_toolchain = "use_cargo_toolchain",
)

find_cargo = _find_cargo
find_cargo_toolchain = _find_cargo_toolchain
use_cargo_toolchain = _use_cargo_toolchain
