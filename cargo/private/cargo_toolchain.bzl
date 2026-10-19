"""The `cargo_toolchain` rule and helpers for rules which run Cargo."""

# buildifier: disable=bzl-visibility
load("//rust/private:lint_test.bzl", "rlocationpath")

CARGO_TOOLCHAIN_TYPE = Label("//cargo:toolchain_type")

def _cargo_toolchain_impl(ctx):
    cargo = ctx.file.cargo

    make_variables = {
        "CARGO": cargo.path,
        "CARGO_RLOCATIONPATH": rlocationpath(cargo, ctx.workspace_name),
    }
    make_variable_info = platform_common.TemplateVariableInfo(make_variables)

    toolchain = platform_common.ToolchainInfo(
        cargo = cargo,
        all_files = depset([cargo]),
        make_variables = make_variable_info,
    )

    return [
        toolchain,
        make_variable_info,
    ]

cargo_toolchain = rule(
    doc = """\
A toolchain providing a [Cargo](https://doc.rust-lang.org/cargo/) binary.

Rules which run Cargo on the execution platform, such as `crates_vendor` and
`cargo_build_script`, resolve `@rules_rust//cargo:toolchain_type` and use the
binary it provides. The toolchain carries Cargo alone, so a host that only
needs Cargo, for example to resolve dependencies, fetches neither `rustc` nor
a standard library. The `rust` module extension registers one for every
platform it registers Rust toolchains for, at `rules_rust`'s default Rust
version.

`$(CARGO)` and `$(CARGO_RLOCATIONPATH)` are available as Make variables to
targets which list `@rules_rust//cargo:current_cargo_toolchain`, a
`cargo_toolchain_alias`, in `toolchains`.
""",
    implementation = _cargo_toolchain_impl,
    attrs = {
        "cargo": attr.label(
            doc = "The `cargo` binary. Can be a direct source or a filegroup containing one item.",
            allow_single_file = True,
            cfg = "exec",
            mandatory = True,
        ),
    },
)

def _cargo_toolchain_alias_impl(ctx):
    toolchain = ctx.toolchains[str(CARGO_TOOLCHAIN_TYPE)]
    if not toolchain:
        if ctx.attr.mandatory:
            fail("{}: no `cargo_toolchain` is registered for the current platform".format(ctx.label))
        return []

    return [
        toolchain,
        toolchain.make_variables,
        DefaultInfo(
            files = depset([toolchain.cargo]),
            runfiles = ctx.runfiles(transitive_files = toolchain.all_files),
        ),
    ]

cargo_toolchain_alias = rule(
    doc = """\
A target standing in for the `cargo_toolchain` resolved for the current platform.

The alias forwards the toolchain's providers, its Make variables (`$(CARGO)`,
`$(CARGO_RLOCATIONPATH)`) and the `cargo` binary.
`@rules_rust//cargo:current_cargo_toolchain` is the alias `rules_rust`
declares.

This follows `cc_toolchain_alias` from `rules_cc`.
""",
    implementation = _cargo_toolchain_alias_impl,
    attrs = {
        "mandatory": attr.bool(
            doc = "Whether to fail when no toolchain is registered. When `False`, the target provides nothing instead.",
            default = True,
        ),
    },
    toolchains = [
        config_common.toolchain_type(str(CARGO_TOOLCHAIN_TYPE), mandatory = False),
    ],
)

def use_cargo_toolchain(mandatory = True):
    """The `toolchains` entries a rule needs to resolve a `cargo_toolchain`.

    Args:
        mandatory (bool): Whether analysis fails when no `cargo_toolchain` is
            registered. Rules which can fall back to the `cargo` of the
            `rust_toolchain` pass `False` and call `find_cargo`.

    Returns:
        list: Toolchain type declarations for a rule's `toolchains` attribute.
    """
    return [config_common.toolchain_type(str(CARGO_TOOLCHAIN_TYPE), mandatory = mandatory)]

def find_cargo_toolchain(ctx):
    """The `cargo_toolchain` resolved for `ctx`, or `None` when none is registered.

    Args:
        ctx (ctx): The rule context. The rule must declare
            `use_cargo_toolchain()` in `toolchains`.

    Returns:
        ToolchainInfo: The toolchain, or `None`.
    """
    return ctx.toolchains[str(CARGO_TOOLCHAIN_TYPE)]

def find_cargo(ctx, rust_toolchain):
    """The Cargo binary a rule should run, and the files it needs at run time.

    The registered `cargo_toolchain` is preferred. When none is registered the
    `cargo` of the `rust_toolchain` is used, which is how rules found Cargo
    before `@rules_rust//cargo:toolchain_type` existed.

    Args:
        ctx (ctx): The rule context. The rule must declare
            `use_cargo_toolchain(mandatory = False)` in `toolchains`.
        rust_toolchain (ToolchainInfo): The resolved `rust_toolchain`, or `None`.

    Returns:
        struct: `cargo`, the binary (a `File`, or `None` when neither toolchain
            provides one), and `files`, a `depset` to add to the action's tools.
    """
    cargo_toolchain = find_cargo_toolchain(ctx)
    if cargo_toolchain:
        return struct(cargo = cargo_toolchain.cargo, files = cargo_toolchain.all_files)
    cargo = rust_toolchain.cargo if rust_toolchain else None
    return struct(cargo = cargo, files = depset([cargo] if cargo else []))
