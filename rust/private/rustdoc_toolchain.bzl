"""The `rustdoc_toolchain` rule and helpers for rules which run rustdoc."""

load("//rust/private:common.bzl", "rust_common")
load("//rust/private:lint_test.bzl", "rlocationpath")
load("//rust/private:sysroot.bzl", "symlink_sysroot_bin", "symlink_sysroot_tree")

def _rustdoc_toolchain_impl(ctx):
    name = ctx.label.name

    # `rustdoc` is a rustc driver: it loads `librustc_driver` from `../lib`
    # relative to itself, so the toolchain reproduces the `bin/` + `lib/`
    # layout of a Rust distribution around the symlinked binary. See
    # `//rust/private:sysroot.bzl`.
    rustdoc = symlink_sysroot_bin(ctx, name, "bin", ctx.file.rustdoc)

    rustc_lib = depset()
    if ctx.attr.rustc_lib:
        rustc_lib = symlink_sysroot_tree(ctx, name, ctx.attr.rustc_lib)

    make_variables = {
        "RUSTDOC": rustdoc.path,
        "RUSTDOC_RLOCATIONPATH": rlocationpath(rustdoc, ctx.workspace_name),
    }
    make_variable_info = platform_common.TemplateVariableInfo(make_variables)

    toolchain = platform_common.ToolchainInfo(
        rustdoc = rustdoc,
        rustc_lib = rustc_lib,
        all_files = depset([rustdoc], transitive = [rustc_lib]),
        make_variables = make_variable_info,
    )

    return [
        toolchain,
        make_variable_info,
    ]

rustdoc_toolchain = rule(
    doc = """\
A toolchain providing [rustdoc](https://doc.rust-lang.org/rustdoc/).

`rust_doc` and `rust_doc_test` resolve `@rules_rust//rust/rustdoc:toolchain_type`
and run the `rustdoc` it provides against the `rust_toolchain` resolved for the
same platform, whose sysroot supplies the standard library. `cargo_build_script`
hands it to build scripts as `$RUSTDOC`. `rustdoc` must come from the same Rust
release as that `rustc`; the `rust` module extension registers one
`rustdoc_toolchain` next to every `rust_toolchain` it registers, from the same
distribution, so the two always match.

The toolchain carries only `rustdoc` and the `librustc_driver` libraries it is
linked against, so compile actions which do not run rustdoc do not depend on
it. The `rust_doc` attribute of `rust_toolchain` is deprecated in favor of this
rule and is consulted only when no `rustdoc_toolchain` is registered.

`$(RUSTDOC)` and `$(RUSTDOC_RLOCATIONPATH)` are available as Make variables to
targets which list `@rules_rust//rust/toolchain:current_rustdoc_toolchain`, a
`rustdoc_toolchain_alias`, in `toolchains`.
""",
    implementation = _rustdoc_toolchain_impl,
    attrs = {
        "rustc_lib": attr.label(
            doc = (
                "The libraries `rustdoc` is linked against (`librustc_driver` and friends), " +
                "laid out as they are in the Rust distribution. Normally the `rustc_lib` of the " +
                "matching `rust_toolchain`."
            ),
            cfg = "exec",
        ),
        "rustdoc": attr.label(
            doc = "The `rustdoc` binary. Can be a direct source or a filegroup containing one item.",
            allow_single_file = True,
            cfg = "exec",
            mandatory = True,
        ),
    },
)

def _rustdoc_toolchain_alias_impl(ctx):
    toolchain = ctx.toolchains[rust_common.rustdoc_toolchain_type]
    if not toolchain:
        if ctx.attr.mandatory:
            fail("{}: no `rustdoc_toolchain` is registered for the current platform".format(ctx.label))
        return []

    return [
        toolchain,
        toolchain.make_variables,
        DefaultInfo(
            files = depset([toolchain.rustdoc]),
            runfiles = ctx.runfiles(transitive_files = toolchain.all_files),
        ),
    ]

rustdoc_toolchain_alias = rule(
    doc = """\
A target standing in for the `rustdoc_toolchain` resolved for the current platform.

The alias forwards the toolchain's providers, its Make variables (`$(RUSTDOC)`,
`$(RUSTDOC_RLOCATIONPATH)`) and the `rustdoc` binary, with the libraries it
needs at run time as runfiles.
`@rules_rust//rust/toolchain:current_rustdoc_toolchain` is the alias
`rules_rust` declares.

This follows `cc_toolchain_alias` from `rules_cc`.
""",
    implementation = _rustdoc_toolchain_alias_impl,
    attrs = {
        "mandatory": attr.bool(
            doc = "Whether to fail when no toolchain is registered. When `False`, the target provides nothing instead.",
            default = True,
        ),
    },
    toolchains = [
        config_common.toolchain_type(rust_common.rustdoc_toolchain_type, mandatory = False),
    ],
)

def find_rustdoc(ctx, rust_toolchain):
    """The rustdoc binary a rule should run, and the files it needs at run time.

    The registered `rustdoc_toolchain` is preferred. When none is registered the
    `rust_doc` of the `rust_toolchain` is used, which is how rules found rustdoc
    before `@rules_rust//rust/rustdoc:toolchain_type` existed.

    Args:
        ctx (ctx): The rule context. The rule must list
            `config_common.toolchain_type(rust_common.rustdoc_toolchain_type, mandatory = False)`
            in `toolchains`.
        rust_toolchain (ToolchainInfo): The resolved `rust_toolchain`, or `None`.

    Returns:
        struct: `rustdoc`, the binary (a `File`, or `None` when neither toolchain
            provides one), and `files`, a `depset` to add to the action's tools.
    """
    rustdoc_toolchain = ctx.toolchains[rust_common.rustdoc_toolchain_type]
    if rustdoc_toolchain:
        return struct(rustdoc = rustdoc_toolchain.rustdoc, files = rustdoc_toolchain.all_files)
    rustdoc = rust_toolchain.rust_doc if rust_toolchain else None
    return struct(rustdoc = rustdoc, files = depset([rustdoc] if rustdoc else []))
