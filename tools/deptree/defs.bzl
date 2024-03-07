"""Rules for ensuring Rust targets are depending on what they use"""

load(
    "//tools/deptree/private:rust_deptree.bzl",
    _rust_deptree_aspect = "rust_deptree_aspect",
)

rust_deptree_aspect = _rust_deptree_aspect
