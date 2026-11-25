"""Tests for `//rust/private/libc:platform_libc` and its precedence over the C++ toolchain's libc."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

_ProbeInfo = provider(
    doc = "What `select()`s on the libc flags resolved to.",
    fields = {
        "libc": "str: `//rust/private/libc:libc`, the combined answer: `glibc`, `musl` or `default`.",
        "platform_libc": "str: `//rust/private/libc:platform_libc`: `glibc`, `musl` or `default`.",
    },
)

def _probe_impl(ctx):
    return [_ProbeInfo(libc = ctx.attr.libc, platform_libc = ctx.attr.platform_libc)]

_probe = rule(
    implementation = _probe_impl,
    attrs = {
        "libc": attr.string(mandatory = True),
        "platform_libc": attr.string(mandatory = True),
    },
)

def _platform_libc_test_impl(ctx):
    env = analysistest.begin(ctx)
    info = analysistest.target_under_test(env)[_ProbeInfo]
    asserts.equals(env, ctx.attr.expected_platform_libc, info.platform_libc, "`:platform_libc`")
    asserts.equals(env, ctx.attr.expected_libc, info.libc, "`:libc`")
    return analysistest.end(env)

def _make_test(platform, extra_toolchains = []):
    return analysistest.make(
        _platform_libc_test_impl,
        attrs = {
            "expected_libc": attr.string(mandatory = True),
            "expected_platform_libc": attr.string(mandatory = True),
        },
        config_settings = {
            "//command_line_option:extra_toolchains": [str(Label("//test/unit/libc:" + t)) for t in extra_toolchains],
            "//command_line_option:platforms": str(Label("//test/unit/libc:" + platform)),
        },
    )

# Served by the C++ toolchain of `libc_test_suite` reporting `local`, which
# names no libc, so that only the platform source can speak; `--extra_toolchains`
# outranks the module's registered C++ toolchains.
undeclared_test = _make_test("undeclared", ["cc_toolchain_local"])
declares_glibc_test = _make_test("declares_glibc", ["cc_toolchain_local"])
declares_musl_test = _make_test("declares_musl", ["cc_toolchain_local"])
declares_both_test = _make_test("declares_both", ["cc_toolchain_local"])

# The platform declares musl while the resolved C++ toolchain links glibc:
# the platform takes precedence where it speaks.
precedence_test = _make_test("declares_musl_with_glibc_cc", ["cc_toolchain_glibc_versioned"])

def platform_libc_test_suite(name):
    """Entry-point macro for the platform libc tests.

    Args:
        name (str): The name of the test suite.
    """
    for setting, flag in {
        "libc": "//rust/private/libc:libc",
        "platform_libc": "//rust/private/libc:platform_libc",
    }.items():
        for libc in ["glibc", "musl"]:
            native.config_setting(
                name = "{}_is_{}".format(setting, libc),
                flag_values = {flag: libc},
            )

    _probe(
        name = "platform_probe",
        libc = select({
            ":libc_is_glibc": "glibc",
            ":libc_is_musl": "musl",
            "//conditions:default": "default",
        }),
        platform_libc = select({
            ":platform_libc_is_glibc": "glibc",
            ":platform_libc_is_musl": "musl",
            "//conditions:default": "default",
        }),
    )

    linux = ["@platforms//cpu:x86_64", "@platforms//os:linux", ":case_local"]
    glibc = ["@platforms_contrib//os/linux/libc/glibc:available"]
    musl = ["@platforms_contrib//os/linux/libc/musl:available"]
    native.platform(name = "undeclared", constraint_values = linux)
    native.platform(name = "declares_glibc", constraint_values = linux + glibc)
    native.platform(name = "declares_musl", constraint_values = linux + musl)
    native.platform(name = "declares_both", constraint_values = linux + glibc + musl)

    # Served by the C++ toolchain of `libc_test_suite` reporting `glibc-2.31`.
    native.platform(
        name = "declares_musl_with_glibc_cc",
        constraint_values = ["@platforms//cpu:x86_64", "@platforms//os:linux", ":case_glibc_versioned"] + musl,
    )

    undeclared_test(
        name = "undeclared_test",
        expected_libc = "default",
        expected_platform_libc = "default",
        target_under_test = ":platform_probe",
    )
    declares_glibc_test(
        name = "declares_glibc_test",
        expected_libc = "glibc",
        expected_platform_libc = "glibc",
        target_under_test = ":platform_probe",
    )
    declares_musl_test(
        name = "declares_musl_test",
        expected_libc = "musl",
        expected_platform_libc = "musl",
        target_under_test = ":platform_probe",
    )
    declares_both_test(
        name = "declares_both_test",
        expected_libc = "glibc",
        expected_platform_libc = "glibc",
        target_under_test = ":platform_probe",
    )
    precedence_test(
        name = "precedence_test",
        expected_libc = "musl",
        expected_platform_libc = "musl",
        target_under_test = ":platform_probe",
    )

    native.test_suite(
        name = name,
        tests = [
            ":undeclared_test",
            ":declares_glibc_test",
            ":declares_musl_test",
            ":declares_both_test",
            ":precedence_test",
        ],
    )
