"""Define transitive dependencies for `rules_rust` examples

There are some transitive dependencies of the dependencies of the examples' 
dependencies. This file contains the required macros to pull these dependencies
"""

load("@io_bazel_rules_docker//repositories:deps.bzl", container_deps = "deps")
load("@examples//cross_compilation:deps.bzl", "cross_compilation_deps")

# buildifier: disable=unnamed-macro
def transitive_deps_final():
    """Define transitive dependencies for `rules_rust` examples
    """

    container_deps()

    cross_compilation_deps()
