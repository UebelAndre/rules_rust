"""What a tool built from the compiler's crates needs to run.

rustdoc and Clippy are rustc drivers: they link `librustc_driver`, which
`rustc-dev` ships as a dylib only, and find it at run time through an rpath
of `../lib` relative to the executable, as rust-lang's bootstrap arranges.
A tool built here gets the same rpath and the host compiler's libraries laid
out beside it, as its runfiles, so the companion toolchain that runs it can
stage them.
"""

load("@rules_rust//rust:defs.bzl", "rust_common")

# The rpath, and on Linux the linker. rustc-dev's archives hold LLVM bitcode
# (`jemalloc.pic.o` in `tikv_jemalloc_sys`, built with LTO), which neither
# `ld.gold` nor `ld.bfd` reads, and which rust-lang links with the `rust-lld`
# the sysroot carries, as rustc does by default on this target. The C
# toolchain's own `-fuse-ld` comes earlier on the command line, so the last
# word is given here. `$$` is how a `rustc_flags` entry says `$` without Make
# variable expansion.
DRIVER_LINK_FLAGS = select({
    "@rules_rust//rust/platform:macos": ["-Clink-arg=-Wl,-rpath,@loader_path/../lib"],
    "//conditions:default": [
        "-Clink-arg=-Wl,-rpath,$$ORIGIN/../lib",
        "-Zunstable-options",
        "-Clink-self-contained=+linker",
        "-Clinker-features=+lld",
        "-Clink-arg=-fuse-ld=lld",
    ],
})

# The release, as `MODULE.bazel` pins it, for the companion toolchains to
# state theirs: a `rustdoc` only runs with the `rustc` of its own release.
RUST_VERSION = "1.99.1"

def _libraries_beside_impl(ctx):
    toolchain = ctx.toolchains[rust_common.toolchain_type].rust_toolchain_info
    links = []
    for library in toolchain.rustc_lib.to_list():
        if library.extension not in ("so", "dylib") and ".so." not in library.basename:
            continue
        link = ctx.actions.declare_file("lib/" + library.basename)
        ctx.actions.symlink(output = link, target_file = library)
        links.append(link)
    return [DefaultInfo(files = depset(links))]

libraries_beside = rule(
    implementation = _libraries_beside_impl,
    doc = "The compiler's shared libraries, symlinked into `lib/` of this package, for the binaries in its `bin/` to find through their rpath.",
    toolchains = [rust_common.toolchain_type],
)
