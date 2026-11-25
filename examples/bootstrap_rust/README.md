# A standard library built from source

This example builds two standard libraries for the machine that runs it, from
the source of the standard library and with a flag of its own,
`-Cforce-frame-pointers=yes`, and a toolchain carrying each:

- one with `std`, `test`, `proc_macro` and everything they depend on, which a
  hosted program and its tests are built against;
- one with `core`, `compiler_builtins` and `alloc` alone, which a freestanding
  `#![no_std]` program with no C runtime is built against.

Both programs run here, so both are tested. The `rust-std` rust-lang ships was
compiled with their flags; a program with flags of its own compiles the
standard library with them, the way `cargo -Zbuild-std` does.

Nothing in the example names a machine. The toolchains' triples, library
extensions and link flags are `select()`s on the platform building, in
`toolchains.bzl`, over the Unix-like hosts the crate graph is written for:
Linux and macOS on x86_64 and AArch64. The freestanding program is Linux only,
since a static binary without `crt1.o` is not something macOS links.

## What is fetched and what is built

Two things are fetched, both from the same Rust release, `1.99.1` in
`MODULE.bazel`:

- the host toolchain the `rust` extension registers, which builds everything
  that runs on the host, and whose `rustc` and libraries the toolchains here
  are assembled around, through
  `@rules_rust//rust/toolchain:current_rustc_files` and
  `current_rustc_lib_files`;
- `rust-src`, the source of the standard library with its dependencies
  vendored, as `@rust_src`.

Everything else is built from them:

| Target | What it is |
|---|---|
| `//:std_library.std` and 18 more | the standard library: the graph of rust-src's `library/Cargo.lock`, `libc` and the other vendored crates included, as ordinary `rust_library` targets |
| `//:std_library.libc.build_script`, `.std.build_script` | the two build scripts that set cfgs from the target, run with `cargo_build_script` |
| `//:no_std_library.core`, `.compiler_builtins`, `.alloc` | the `no_std` crates |
| `//:std_library`, `//:no_std_library` | each set as a `rust_stdlib_filegroup` |
| `//:std_rust_toolchain`, `//:no_std_rust_toolchain` | the toolchains, with those as their `rust_std` |
| `//:hosted`, `//:hosted_test` | a hosted program and its tests, built with the first |
| `//:freestanding`, `//:freestanding_test` | a program with no standard library and no C runtime, built with the second, and a test of the exit status it computes |

## How the standard library gets built

`std_from_source.bzl` is part of the example, not of rules_rust. It is a macro
over public pieces: `rust_library` for each crate, `cargo_build_script` for the
two build scripts, `rust_stdlib_filegroup` for the result, and a transition
that chooses the toolchain. The crate graph it encodes, names, features and
editions, is that of one release's `library/`, which is why it belongs next to
the `MODULE.bazel` that pins the release.

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

## What is left out

- `backtrace`. The `std` feature pulls in `addr2line`, `gimli`, `object` and
  `miniz_oxide`; without it `std::backtrace` reports itself unsupported.
- A dylib `std`. Only rlibs are built, so `link_std_dylib` is not available
  with these toolchains, and proc macros, which link `std` dynamically, are
  compiled with the host's registered toolchain, as Cargo does under
  `-Zbuild-std`.
- Windows, which needs the `windows-*` crates in `libc`'s place.

## Versions

The compiler and `rust-src` have to come from one release: the standard
library uses unstable features that only the compiler of its own release is
guaranteed to have. That is why `1.99.1` is the one version in `MODULE.bazel`.

The host toolchain is downloaded, not built. Building `rustc` from source is a
larger step, since the compiler needs LLVM and its crate graph, and it carries
its own version rule: the sources of release `X.Y` build with a compiler of
release `X.Y` or `X.(Y-1)` and no other, which the downloaded release of the
same version satisfies.

## Try it

```
bazel test //...
```

builds both standard libraries and the programs, runs `//:hosted_test`
through the `test` crate built here, and runs `//:freestanding` for its exit
status. To look at the programs:

```
$(bazel cquery --output=files //:hosted)
file $(bazel cquery --output=files //:freestanding)
```
