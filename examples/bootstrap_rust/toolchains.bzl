"""What a toolchain for the machine building this example looks like.

The toolchains in `BUILD.bazel` are for whichever platform is building, so
their triple, library extensions and link flags are `select()`s on it rather
than constants. rules_rust declares a `config_setting` per triple it supports
and per operating system under `@rules_rust//rust/platform`.
"""

load("@rules_rust//rust/platform:triple_mappings.bzl", "system_to_stdlib_linkflags")

# The hosts this example runs on: Unix-like with a C library, which is what
# the crate graph in `std_from_source.bzl` is written for.
HOST_TRIPLES = [
    "aarch64-apple-darwin",
    "aarch64-unknown-linux-gnu",
    "x86_64-apple-darwin",
    "x86_64-unknown-linux-gnu",
]

HOST_TRIPLE = select(
    {"@rules_rust//rust/platform:" + triple: triple for triple in HOST_TRIPLES},
    no_match_error = "the bootstrap_rust example builds on these hosts: {}".format(", ".join(HOST_TRIPLES)),
)

DYLIB_EXT = select({
    "@rules_rust//rust/platform:macos": ".dylib",
    "//conditions:default": ".so",
})

# What a C link of a Rust library needs beside it, as rules_rust's generated
# toolchains state it for each system.
STDLIB_LINKFLAGS = select({
    "@rules_rust//rust/platform:macos": system_to_stdlib_linkflags("darwin"),
    "//conditions:default": system_to_stdlib_linkflags("linux"),
})

# A program without a standard library links no C runtime and makes its own
# system calls, which on Linux takes a static link without `crt1.o`. The
# flags apply to the standard library and the program alike, and the panic
# strategy must, since `core` and the program share it.
NO_STD_FLAGS = ["-Cpanic=abort"] + select({
    "@rules_rust//rust/platform:linux": [
        "-Crelocation-model=static",
        "-Clink-arg=-nostartfiles",
        "-Clink-arg=-nostdlib",
        "-Clink-arg=-static",
    ],
    "//conditions:default": [],
})
