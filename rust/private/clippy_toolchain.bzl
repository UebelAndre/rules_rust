"""The `clippy_toolchain` rule and helpers for rules which run Clippy."""

load("//rust/private:common.bzl", "rust_common")
load("//rust/private:lint_test.bzl", "rlocationpath")
load("//rust/private:sysroot.bzl", "symlink_sysroot_bin", "symlink_sysroot_tree")

def _clippy_toolchain_impl(ctx):
    name = ctx.label.name

    # `clippy-driver` is a rustc driver: it loads `librustc_driver` from
    # `../lib` relative to itself, so the toolchain reproduces the `bin/` +
    # `lib/` layout of a Rust distribution around the symlinked binary. See
    # `//rust/private:sysroot.bzl`.
    clippy_driver = symlink_sysroot_bin(ctx, name, "bin", ctx.file.clippy_driver)
    direct_files = [clippy_driver]

    cargo_clippy = None
    if ctx.file.cargo_clippy:
        cargo_clippy = symlink_sysroot_bin(ctx, name, "bin", ctx.file.cargo_clippy)
        direct_files.append(cargo_clippy)

    rustc_lib = depset()
    if ctx.attr.rustc_lib:
        rustc_lib = symlink_sysroot_tree(ctx, name, ctx.attr.rustc_lib)

    make_variables = {
        "CLIPPY_DRIVER": clippy_driver.path,
        "CLIPPY_DRIVER_RLOCATIONPATH": rlocationpath(clippy_driver, ctx.workspace_name),
    }
    if cargo_clippy:
        make_variables.update({
            "CARGO_CLIPPY": cargo_clippy.path,
            "CARGO_CLIPPY_RLOCATIONPATH": rlocationpath(cargo_clippy, ctx.workspace_name),
        })
    make_variable_info = platform_common.TemplateVariableInfo(make_variables)

    toolchain = platform_common.ToolchainInfo(
        clippy_driver = clippy_driver,
        cargo_clippy = cargo_clippy,
        rustc_lib = rustc_lib,
        all_files = depset(direct_files, transitive = [rustc_lib]),
        make_variables = make_variable_info,
    )

    return [
        toolchain,
        make_variable_info,
    ]

clippy_toolchain = rule(
    doc = """\
A toolchain providing [Clippy](https://doc.rust-lang.org/clippy/).

`rust_clippy_aspect`, `rust_clippy` and `rust_clippy_test` resolve
`@rules_rust//rust/clippy:toolchain_type` and run the `clippy-driver` it
provides against the `rust_toolchain` resolved for the same platform, whose
sysroot supplies the standard library. `clippy-driver` must come from the same
Rust release as that `rustc`; the `rust` module extension registers one
`clippy_toolchain` next to every `rust_toolchain` it registers, from the same
distribution, so the two always match.

The toolchain carries only Clippy and the `librustc_driver` libraries it is
linked against, so compile actions which do not run Clippy do not depend on
it. The `clippy_driver` and `cargo_clippy` attributes of `rust_toolchain` are
deprecated in favor of this rule and are consulted only when no
`clippy_toolchain` is registered.

`$(CLIPPY_DRIVER)`, `$(CLIPPY_DRIVER_RLOCATIONPATH)` and, when `cargo_clippy`
is set, `$(CARGO_CLIPPY)` and `$(CARGO_CLIPPY_RLOCATIONPATH)` are available as
Make variables to targets which list
`@rules_rust//rust/toolchain:current_clippy_toolchain`, a
`clippy_toolchain_alias`, in `toolchains`.
""",
    implementation = _clippy_toolchain_impl,
    attrs = {
        "cargo_clippy": attr.label(
            doc = "The `cargo-clippy` binary. Can be a direct source or a filegroup containing one item.",
            allow_single_file = True,
            cfg = "exec",
        ),
        "clippy_driver": attr.label(
            doc = "The `clippy-driver` binary. Can be a direct source or a filegroup containing one item.",
            allow_single_file = True,
            cfg = "exec",
            mandatory = True,
        ),
        "rustc_lib": attr.label(
            doc = (
                "The libraries `clippy-driver` is linked against (`librustc_driver` and friends), " +
                "laid out as they are in the Rust distribution. Normally the `rustc_lib` of the " +
                "matching `rust_toolchain`."
            ),
            cfg = "exec",
        ),
    },
)

def _clippy_toolchain_alias_impl(ctx):
    toolchain = ctx.toolchains[rust_common.clippy_toolchain_type]
    if not toolchain:
        if ctx.attr.mandatory:
            fail("{}: no `clippy_toolchain` is registered for the current platform".format(ctx.label))
        return []

    return [
        toolchain,
        toolchain.make_variables,
        DefaultInfo(
            files = depset([toolchain.clippy_driver]),
            runfiles = ctx.runfiles(transitive_files = toolchain.all_files),
        ),
    ]

clippy_toolchain_alias = rule(
    doc = """\
A target standing in for the `clippy_toolchain` resolved for the current platform.

The alias forwards the toolchain's providers, its Make variables
(`$(CLIPPY_DRIVER)`, `$(CARGO_CLIPPY)`, ...) and the `clippy-driver` binary,
with the libraries it needs at run time as runfiles.
`@rules_rust//rust/toolchain:current_clippy_toolchain` is the alias
`rules_rust` declares.

This follows `cc_toolchain_alias` from `rules_cc`.
""",
    implementation = _clippy_toolchain_alias_impl,
    attrs = {
        "mandatory": attr.bool(
            doc = "Whether to fail when no toolchain is registered. When `False`, the target provides nothing instead.",
            default = True,
        ),
    },
    toolchains = [
        config_common.toolchain_type(rust_common.clippy_toolchain_type, mandatory = False),
    ],
)

def find_clippy(ctx, rust_toolchain):
    """The Clippy binaries a rule should run, and the files they need at run time.

    The registered `clippy_toolchain` is preferred. When none is registered the
    `clippy_driver` and `cargo_clippy` of the `rust_toolchain` are used, which
    is how rules found Clippy before `@rules_rust//rust/clippy:toolchain_type`
    existed.

    Args:
        ctx (ctx): The rule context. The rule must list
            `config_common.toolchain_type(rust_common.clippy_toolchain_type, mandatory = False)`
            in `toolchains`.
        rust_toolchain (ToolchainInfo): The resolved `rust_toolchain`, or `None`.

    Returns:
        struct: `clippy_driver`, the binary (a `File`, or `None` when neither
            toolchain provides one), `cargo_clippy`, the `cargo-clippy` binary
            (a `File` or `None`), and `files`, a `depset` to add to the
            action's tools.
    """
    clippy_toolchain = ctx.toolchains[rust_common.clippy_toolchain_type]
    if clippy_toolchain:
        return struct(
            clippy_driver = clippy_toolchain.clippy_driver,
            cargo_clippy = clippy_toolchain.cargo_clippy,
            files = clippy_toolchain.all_files,
        )
    clippy_driver = rust_toolchain.clippy_driver if rust_toolchain else None
    cargo_clippy = rust_toolchain.cargo_clippy if rust_toolchain else None
    return struct(
        clippy_driver = clippy_driver,
        cargo_clippy = cargo_clippy,
        files = depset([f for f in [clippy_driver, cargo_clippy] if f]),
    )
