"""The C standard library of the resolved C++ toolchain, as a flag."""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")

def _without_version(libc):
    """Strips a version suffix from a `target_libc` value, as `@rules_cc//cc/libc` does.

    Bazel documents `target_libc` as a version string such as `glibc-2.2.2`, so
    everything from the first `-` followed by a digit is dropped; names like
    `wasi-libc` stay whole.

    Args:
        libc (str): The `libc` of a `CcToolchainInfo`.

    Returns:
        str: The name of the C standard library.
    """
    for i in range(1, len(libc) - 1):
        if libc[i] == "-" and libc[i + 1].isdigit():
            return libc[:i]
    return libc

def _cc_toolchain_libc_flag_impl(ctx):
    # The libc a target links is the one its C++ toolchain links: the same
    # `target_libc` the settings of `@rules_cc//cc/libc` read, so that Rust and
    # C++ code of one build never disagree on it. Without a C++ toolchain
    # there is nothing to link against and the value is empty, which no
    # setting matches: a `select()` on them takes its default.
    #
    # `platform.bzl` answers the same question from the platform's side and
    # takes precedence in `:libc`; this source goes away once platforms
    # commonly declare their libc.
    cc_toolchain = find_cc_toolchain(ctx, mandatory = False)
    libc = _without_version(cc_toolchain.libc) if cc_toolchain else ""
    return [config_common.FeatureFlagInfo(value = libc)]

cc_toolchain_libc_flag = rule(
    doc = """\
Exposes the C standard library of the resolved C++ toolchain to `select()`.

The value is the toolchain's `target_libc` without its version suffix, e.g.
`glibc` or `musl`, the value `@rules_cc//cc/libc` reads, or empty without a
C++ toolchain. Unlike that package, this rule tolerates a configuration without
a C++ toolchain and needs no particular version of rules_cc.

A `config_setting` on this flag cannot be used in the `target_settings` of a
`toolchain`, as Bazel rejects a setting which itself resolves a toolchain
there; the toolchains of rules_rust use the settings in `select()`s on their
own attributes instead.
""",
    implementation = _cc_toolchain_libc_flag_impl,
    toolchains = use_cc_toolchain(mandatory = False),
)
