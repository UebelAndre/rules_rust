# A Rust toolchain built from source

This example builds, for the machine that runs it, everything on a Rust
toolchain but the compiler itself: two standard libraries, rustdoc, Clippy,
Cargo and rust-analyzer, each from the source of one Rust release, and each
with a test that uses it.

The compiler is the one the `rust` extension downloads. Building `rustc` from
source is a larger step, since the compiler needs LLVM and its crate graph,
and it carries its own version rule: the sources of release `X.Y` build with a
compiler of release `X.Y` or `X.(Y-1)` and no other, which the downloaded
release of the same version satisfies.

Nothing in the example names a machine. The toolchains' triples, library
extensions and link flags are `select()`s on the platform building, in
`toolchains.bzl`, over the Unix-like hosts the standard library's crate graph
is written for: Linux and macOS on x86_64 and AArch64. CI builds and tests it
on Linux.

## What is fetched and what is built

Fetched, all of release `1.99.1` as `MODULE.bazel` pins it:

- the host toolchain the `rust` extension registers, with `rustc-dev`, the
  compiler's crates as a library, which rustdoc and Clippy link. It builds
  everything that runs on the host, and its `rustc` and libraries are what
  the toolchains here are assembled around, through
  `@rules_rust//rust/toolchain:current_rustc_files` and
  `current_rustc_lib_files`;
- `rustc-1.99.1-src.tar.xz`, the release's source tree, as `@rust_src`:
  `library/`, rustdoc and Clippy under `src/`, and every crate they depend on
  vendored under `vendor/`;
- the third-party crates of rustdoc and Clippy from crates.io, as
  `@tool_crates`;
- Cargo from `rust-lang/cargo` at the commit the release's submodule pins, and
  rust-analyzer from `rust-lang/rust-analyzer` at the weekly release of the
  tree's last sync, as `@cargo_crates` and `@rust_analyzer_crates`, since
  crate_universe generates a git-sourced workspace whole and these two are
  workspaces of fifty crates each.

Each of the three crate repositories resolves against a `Cargo.lock` copied
from the release, the root's for rustdoc and Clippy, Cargo's and
rust-analyzer's for theirs, and the result is checked in beside it as a
crate_universe lockfile, so every crate is at the version the release built
with. `CARGO_BAZEL_REPIN=1 bazel build //...` regenerates them.

Built:

| Target | What it is | Test |
|---|---|---|
| `//:std_library` | `std`, `test`, `proc_macro` and the sixteen crates they depend on, `libc` and the other vendored crates included, as `rust_library` targets; the build scripts of `libc` and `std` run with `cargo_build_script` | `//:hosted_test`, a `rust_test` through the `test` crate built here |
| `//:no_std_library` | `core`, `compiler_builtins` and `alloc` | `//:freestanding_test`, a program with no C runtime that exits through its own system call |
| `@rust_src//src/tools/rustdoc:bin/rustdoc` | rustdoc, over `//src/librustdoc` and `//src/rustdoc-json-types` | `//:rustdoc_from_source_test`, a `rust_doc` of `//:documented` |
| `@rust_src//src/tools/clippy:bin/clippy-driver`, `bin/cargo-clippy` | Clippy, over its lint, config and utility crates | `//:clippy_from_source_test`, a `rust_clippy_test` of `//:documented` |
| `@cargo_crates//cargo__cargo` | Cargo, with libgit2, curl and sqlite built from the C their `-sys` crates carry and OpenSSL from the `openssl` module | `//:cargo_from_source_test`, `cargo --version` through the `cargo_toolchain` of `//:with_cargo` |
| `@rust_analyzer_crates//rust-analyzer__rust-analyzer` | rust-analyzer | `//:rust_analyzer_from_source_test`, `rust-analyzer --version` |

Each tool is registered as the companion toolchain of its kind. rustdoc,
Clippy and rust-analyzer come ahead of the downloaded ones, so `rust_doc`,
`rust_clippy_test` and whatever resolves a `rust_analyzer_toolchain` get the
ones built here. Cargo cannot: every build script consults the
`cargo_toolchain` for its `CARGO`, the build scripts of Cargo's own crates
included, and a Cargo registered everywhere would have to build itself. Its
toolchain is that of `//:with_cargo`, the host's platform with one more
constraint, which its test is built for.

## How the standard library gets built

`std_from_source.bzl` is part of the example, not of rules_rust. It is a macro
over public pieces: `rust_library` for each crate, `cargo_build_script` for the
two build scripts, `rust_stdlib_filegroup` for the result, and a transition
that chooses the toolchain. The crate graph it encodes, names, features and
editions, is that of one release's `library/`, which is why it belongs next to
the `MODULE.bazel` that pins the release. The vendored crates' versions come
from `library/Cargo.lock`, which `rust_src.bzl` reads into a generated
`vendored.bzl`, so no BUILD file names one.

The toolchain that carries a standard library cannot be the one that builds
it, so `BUILD.bazel` declares each toolchain twice:

1. `//:std_bootstrap_rust_toolchain` has no `rust_std`. The macro declares a
   `toolchain` for it and never registers it. For the crates it builds, and
   for nothing else, a transition puts that `toolchain` ahead of every
   registered one with `--extra_toolchains` and sets `//:building_std`, which
   the `toolchain` is conditioned on. So `core` and the others are compiled by
   a toolchain that passes rustc no standard library and resolves `core`
   through `deps` like any other crate, while the build scripts and tools
   compiled for the host along the way, in a configuration without the
   setting, keep the downloaded standard library. That matters because the
   target is the host.
2. `//:std_rust_toolchain` is the same toolchain with
   `rust_std = ":std_library"`. It is the one `MODULE.bazel` registers, for
   `//:with_std`: the host's platform with a constraint of the example's own,
   so only `//:hosted` and `//:hosted_test`, which name that platform, resolve
   it. Its sysroot lays the rlibs out under `lib/rustlib/<triple>/lib`, where
   rustc looks for a target's libraries, and the host compiler's own copy of
   the standard library stays out of that directory.

The two differ in `rust_std` and nothing else, because the standard library
must be compiled with the flags of the programs that link it. The toolchain
without `std` follows the same pattern for `//:without_std`, with
`-Cpanic=abort` and, on Linux, a static link without the C runtime, flags the
freestanding program needs and `core` must share.

The crates are compiled as rust-lang's bootstrap compiles them, with
`RUSTC_BOOTSTRAP=1` and `-Zforce-unstable-if-unmarked`. The vendored crates
reach `core`, `alloc` and `std` through the `rustc-std-workspace-*` shims,
under the names Cargo's `package =` renames give them, which `aliases`
reproduces. `compiler_builtins`' build script does not run: its `mem`
feature, which provides `memcpy` and friends for a program without a C
library, and the cfgs it would set for the architecture are the macro's
defaults and can be changed through `compiler_builtins_features` and
`compiler_builtins_flags`.

## How the tools get built

rustdoc and Clippy read files relative to `CARGO_MANIFEST_DIR`, rustdoc its
templates and static files, Clippy's build script its own directory, and
rules_rust sets that variable to the package of the target. So their BUILD
files live in the source tree: `rust_src.bzl` writes `BUILD.librustdoc.bazel`
and the others into the packages they are for when it fetches the tarball.
rustdoc's build script minifies and hashes the static files into `OUT_DIR`,
where the library includes them from, so it runs with `cargo_build_script`
like any other.

Both are rustc drivers. They link the compiler's crates through
`#![feature(rustc_private)]`, which `RUSTC_BOOTSTRAP` allows on a stable
compiler, and `rustc-dev` ships `librustc_driver` as a dylib only, found at
run time through an rpath of `../lib` relative to the executable. The
binaries therefore land in a `bin/` directory with the compiler's shared
libraries symlinked into `lib/` beside them (`libraries_beside` in
`tools.bzl`), carried as runfiles, which the companion toolchains stage. They
also link with the `rust-lld` the sysroot carries, as rustc does by default on
this target: `rustc-dev`'s archives hold LLVM bitcode that `ld.gold` and
`ld.bfd` do not read.

Cargo and rust-analyzer are ordinary crates to crate_universe, specs with a
git source, and come out as `rust_binary` targets through `gen_binaries`.
Cargo's C dependencies build themselves from the sources their `-sys` crates
carry, except OpenSSL: `openssl-src` finds its copy through a path baked in at
compile time, which under a sandbox is gone by the time the build script
runs, so `openssl-sys` is pointed at the `openssl` module instead, Bazel's own
build of OpenSSL.

## What is left out

- `backtrace` in `std`. The feature pulls in `addr2line`, `gimli`, `object`
  and `miniz_oxide`; without it `std::backtrace` reports itself unsupported.
- A dylib `std`. Only rlibs are built, so `link_std_dylib` is not available
  with these toolchains, and proc macros, which link `std` dynamically, are
  compiled with the host's registered toolchain, as Cargo does under
  `-Zbuild-std`.
- Windows, which needs the `windows-*` crates in `libc`'s place, and the
  freestanding program on macOS, which does not link a static binary without
  `crt1.o`.
- `rustc`, and with it LLVM.

## Try it

```
bazel test //...
```

builds everything above and runs the six tests. To look at what was built:

```
bazel run //:hosted
file $(bazel cquery --output=files //:freestanding)
bazel run @rust_src//src/tools/rustdoc:bin/rustdoc -- --version
bazel run @rust_src//src/tools/clippy:bin/cargo-clippy -- --version
bazel run @cargo_crates//cargo__cargo -- --version
bazel run @rust_analyzer_crates//rust-analyzer__rust-analyzer -- --version
```

The drivers find the compiler's libraries through their runfiles, which
`bazel run` stages and a path from `cquery` does not.
