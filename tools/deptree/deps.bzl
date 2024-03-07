"""
Dependencies of the rust deps tool.
"""

load("//tools/deptree/3rdparty/crates:defs.bzl", "crate_repositories")

def rust_deptree_dependencies():
    """Define dependencies of the Rust deptree Bazel tools"""
    return crate_repositories()
