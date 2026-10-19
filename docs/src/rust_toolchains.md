# Toolchains

A Rust build in Bazel selects its compiler, standard library, and companion tools
through a set of registered [Bazel toolchains][bazel_toolchains]. `rules_rust`
ships one toolchain type per companion tool so that Rust, `rust-analyzer`, and
`rustfmt` can be resolved independently.

[bazel_toolchains]: https://bazel.build/extending/toolchains

Most users register toolchains via the `rust` module extension (see
[Bzlmod](./rust_bzlmod.md)) rather than declaring these rules directly. The rules
below exist for users who need to define custom toolchains — for example, to point
at a locally built `rustc` or to add a target triple that the extension doesn't
cover.

## Toolchain rules

- [rust_toolchain](./rust_toolchain.md) — Declare a Rust compilation toolchain: the
  `rustc` binary, standard library, linker, and per-target compilation settings.
- [rustfmt_toolchain](./rustfmt_toolchain.md) — Declare a toolchain providing the
  `rustfmt` binary used by [rustfmt](./rustfmt.md) rules.
- [rust_analyzer_toolchain](./rust_analyzer_toolchain.md) — Declare a toolchain
  providing the `rust-analyzer` binary and proc-macro server used by the
  [rust_analyzer](./rust_analyzer.md) integration.

## Toolchain aliases

A toolchain alias is a target that stands in for whichever toolchain Bazel
resolves for the current platform, in the manner of `cc_toolchain_alias` from
`rules_cc`. It forwards the toolchain's providers, Make variables and files, so
a `genrule` or a custom rule can depend on "the Rust toolchain" without naming
one. `rules_rust` declares one alias per toolchain type under
`@rules_rust//rust/toolchain`: `current_rust_toolchain`,
`current_rustfmt_toolchain` and `current_rust_analyzer_toolchain`.

- [rust_toolchain_alias](./rust_toolchain_alias.md) — Alias for the resolved
  `rust_toolchain`.
- [rustfmt_toolchain_alias](./rustfmt_toolchain_alias.md) — Alias for the
  resolved `rustfmt_toolchain`.
- [rust_analyzer_toolchain_alias](./rust_analyzer_toolchain_alias.md) — Alias
  for the resolved `rust_analyzer_toolchain`.

The rules were previously named `current_rust_toolchain`,
`current_rustfmt_toolchain` and `current_rust_analyzer_toolchain`. Those names
remain available and are deprecated; the targets of the same names under
`@rules_rust//rust/toolchain` are unchanged.

## Data rules

- [rust_stdlib_filegroup](./rust_stdlib_filegroup.md) — Group the files of a Rust
  standard library archive into a target that can be attached to a
  `rust_toolchain` via the `rust_std` attribute.
