"""A module defining dependencies for cross-compilation examples"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@io_bazel_rules_docker//container:container.bzl", "container_pull")

def cross_compilation_deps():
    container_pull(
        name = "alpine",
        registry = "docker.io",
        repository = "alpine",
        digest = "sha256:1775bebec23e1f3ce486989bfc9ff3c4e951690df84aa9f926497d82f2ffca9d",
        tag = "3.14.0",
    )
