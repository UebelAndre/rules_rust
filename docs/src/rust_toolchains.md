# Toolchains

A Rust build in Bazel selects its compiler, standard library, and companion tools
through a set of registered [Bazel toolchains][bazel_toolchains]. `rules_rust`
ships one toolchain type per companion tool so that Rust, `rustdoc`, `clippy`,
`rustfmt`, `cargo`, and `rust-analyzer` can be resolved independently, and so
that a compile action depends only on the compiler it runs.

[bazel_toolchains]: https://bazel.build/extending/toolchains

Most users register toolchains via the `rust` module extension (see
[Bzlmod](./rust_bzlmod.md)) rather than declaring these rules directly. The rules
below exist for users who need to define custom toolchains — for example, to point
at a locally built `rustc` or to add a target triple that the extension doesn't
cover.

## Toolchain rules

- [rust_toolchain](./rust_toolchain.md) — Declare a Rust compilation toolchain: the
  `rustc` binary, standard library, linker, and per-target compilation settings.
  Only what every compile action needs lives here; the tools below have
  toolchains of their own so their binaries stay out of compile inputs.
- [rustdoc_toolchain](./rustdoc_toolchain.md) — Declare a toolchain providing the
  `rustdoc` binary used by [rust_doc](./rust_doc.md) and [rust_doc_test](./rust_doc_test.md).
  Build scripts do not see it unless a [cargo_build_script](./cargo_build_script.md)
  lists it in `toolchains` and maps `$(RUSTDOC)` in `build_script_env`. The `rust`
  module extension registers one next to every `rust_toolchain`, from the same
  distribution, since `rustdoc` must match `rustc` exactly. The `rust_doc`
  attribute of `rust_toolchain` is deprecated in its favor and is only consulted
  when no `rustdoc_toolchain` is registered.
- [clippy_toolchain](./clippy_toolchain.md) — Declare a toolchain providing the
  `clippy-driver` (and optionally `cargo-clippy`) binary used by the
  [clippy](./clippy.md) rules. Registered next to every `rust_toolchain` in the
  same way. The `clippy_driver` and `cargo_clippy` attributes of `rust_toolchain`
  are deprecated in its favor and are only consulted when no `clippy_toolchain`
  is registered.
- [rustfmt_toolchain](./rustfmt_toolchain.md) — Declare a toolchain providing the
  `rustfmt` binary used by [rustfmt](./rustfmt.md) rules.
- [rust_analyzer_toolchain](./rust_analyzer_toolchain.md) — Declare a toolchain
  providing the `rust-analyzer` binary and proc-macro server used by the
  [rust_analyzer](./rust_analyzer.md) integration.
- [cargo_toolchain](./cargo_toolchain.md) — Declare a toolchain providing the
  `cargo` binary used by rules which run Cargo, such as
  [cargo_build_script](./cargo_build_script.md) and
  [crates_vendor](./crates_vendor.md). The `rust` module extension declares one
  in the repository of every `rust_toolchain` it registers and registers the two
  together, so Cargo always comes from the same release as `rustc`; the
  toolchain carries the same `version`, `iso_date` and `channel` identifiers and
  `cargo_build_script` fails when they differ. The `cargo` attribute of
  `rust_toolchain` is deprecated in its favor and is only consulted when no
  `cargo_toolchain` is registered.

## Rule author helpers

`rust_common` carries the label of every toolchain type `rules_rust` defines:
`toolchain_type`, `rustdoc_toolchain_type`, `clippy_toolchain_type`,
`rustfmt_toolchain_type`, `rust_analyzer_toolchain_type` and
`cargo_toolchain_type`. A rule declares the ones it needs in `toolchains`, for
example `config_common.toolchain_type(rust_common.clippy_toolchain_type,
mandatory = False)`, and reads them back with `ctx.toolchains[...]`.

While the deprecated `rust_doc`, `clippy_driver`, `cargo_clippy` and `cargo`
attributes of `rust_toolchain` remain, the matching
[find_rustdoc](./rustdoc_toolchain.md#find_rustdoc),
[find_clippy](./clippy_toolchain.md#find_clippy) and
[find_cargo](./cargo_toolchain.md#find_cargo) helpers prefer the registered
toolchain and fall back to those attributes.

## Data rules

- [rust_stdlib_filegroup](./rust_stdlib_filegroup.md) — Group the files of a Rust
  standard library archive into a target that can be attached to a
  `rust_toolchain` via the `rust_std` attribute.

## Linux libc (glibc vs musl)

The CPU and OS of a toolchain's target triple map to constraints from `@platforms`
(see `triple_to_constraint_set` in `@rules_rust//rust/platform:triple_mappings.bzl`).
That alone makes `x86_64-unknown-linux-gnu` and `x86_64-unknown-linux-musl`
indistinguishable, so the `rust` extension registers a single toolchain per
Linux CPU, named after the triple without its libc (e.g.
`rust_linux_x86_64__x86_64-unknown-linux__stable`). Toolchain resolution
therefore has exactly one candidate for any Linux platform, and the toolchain
picks the libc itself. The libc of a build is what the platform declares
available through the constraints of
[platforms_contrib](https://github.com/bazel-contrib/platforms_contrib),
`@platforms_contrib//os/linux/libc/{glibc,musl}:available`, glibc for a platform
declaring both, and, where the platform declares none, what the resolved C++
toolchain links, its `target_libc` as `@rules_cc//cc/libc` reads it, so that Rust
code and C code are never linked against different ones. The toolchain's
`rust_std` and `target_triple` are `select()`s on it for
the target platform, and its `rustc` and other tools are aliases selecting the
glibc or musl compiler on it for the execution platform, with the
`rust_toolchain` reporting the matching `exec_triple`. A C++ toolchain which
does not name its libc, or a platform without one, gets the toolchain's
default: glibc, unless the toolchain runs on musl.

The CPU of the execution platform gets both standard libraries and, where Rust
ships them, both compilers without configuration, fetched only once a C++
toolchain of that libc is in use. For other CPUs the musl triple has to be among
the toolchain's `extra_target_triples`; a toolchain without the standard
library a C++ toolchain asks for falls back to its default.

So building for musl is a matter of the C++ toolchain. With the musl toolchains
of [toolchains_musl](https://github.com/bazel-contrib/musl-toolchain), which
report `musl`, constrained to platforms declaring musl:

```python
platform(
    name = "linux_x86_64_musl",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
        "@platforms_contrib//os/linux/libc/musl:available",
    ],
)
```

`--platforms=//:linux_x86_64_musl` selects the musl C++ toolchain and the musl
standard library alike. `rust.repository_set` registers exactly the toolchains
it is given, one per triple, as
[`examples/cross_compile_musl`](https://github.com/bazelbuild/rules_rust/tree/main/examples/cross_compile_musl)
shows.
