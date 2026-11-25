"""Tests for the `//rust/private/libc` settings, which follow the C++ toolchain's libc."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc:defs.bzl", "cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")

# A C++ toolchain reporting `target_libc`, as toolchains in the wild do:
# the autoconfigured toolchain says `glibc`, `musl` or, before rules_cc
# 0.2.23, `local`; toolchains_musl says `musl`; Bazel documents versioned
# values such as `glibc-2.31`.
def _cc_config_impl(ctx):
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "test-" + ctx.attr.target_libc,
        host_system_name = "unknown",
        target_system_name = "unknown",
        target_cpu = "unknown",
        target_libc = ctx.attr.target_libc,
        compiler = "unknown",
        abi_version = "unknown",
        abi_libc_version = "unknown",
    )

_cc_config = rule(
    implementation = _cc_config_impl,
    attrs = {"target_libc": attr.string(mandatory = True)},
    provides = [CcToolchainConfigInfo],
)

_ProbeInfo = provider(
    doc = "What a `select()` on the libc settings resolved to.",
    fields = {"libc": "str: `glibc`, `musl` or `default`."},
)

def _probe_impl(ctx):
    return [_ProbeInfo(libc = ctx.attr.libc)]

_probe = rule(
    implementation = _probe_impl,
    attrs = {"libc": attr.string(mandatory = True)},
)

def _libc_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.equals(env, ctx.attr.expected, analysistest.target_under_test(env)[_ProbeInfo].libc)
    return analysistest.end(env)

def _make_libc_test(platform):
    return analysistest.make(
        _libc_test_impl,
        attrs = {"expected": attr.string(mandatory = True)},
        config_settings = {
            "//command_line_option:extra_toolchains": [
                str(Label("//test/unit/libc:cc_toolchain_glibc_versioned")),
                str(Label("//test/unit/libc:cc_toolchain_musl")),
                str(Label("//test/unit/libc:cc_toolchain_local")),
            ],
            "//command_line_option:platforms": str(Label("//test/unit/libc:" + platform)),
        },
    )

glibc_versioned_test = _make_libc_test("glibc_versioned")
musl_test = _make_libc_test("musl")
local_test = _make_libc_test("local")
no_cc_toolchain_test = _make_libc_test("no_cc_toolchain")

def libc_test_suite(name):
    """Entry-point macro for the libc settings tests.

    Args:
        name (str): The name of the test suite.
    """
    native.filegroup(name = "empty")

    # One platform per C++ toolchain, told apart by a constraint of their own
    # so that the host's toolchain never matches them.
    native.constraint_setting(name = "case")
    for case, target_libc in {
        "glibc_versioned": "glibc-2.31",
        "local": "local",
        "musl": "musl",
    }.items():
        native.constraint_value(name = "case_" + case, constraint_setting = ":case")
        native.platform(
            name = case,
            constraint_values = ["@platforms//cpu:x86_64", "@platforms//os:linux", ":case_" + case],
        )
        _cc_config(name = "cc_config_" + case, target_libc = target_libc)
        cc_toolchain(
            name = "cc_toolchain_impl_" + case,
            all_files = ":empty",
            compiler_files = ":empty",
            dwp_files = ":empty",
            linker_files = ":empty",
            objcopy_files = ":empty",
            strip_files = ":empty",
            supports_param_files = 0,
            toolchain_config = ":cc_config_" + case,
            toolchain_identifier = "test-" + case,
        )
        native.toolchain(
            name = "cc_toolchain_" + case,
            target_compatible_with = [":case_" + case],
            toolchain = ":cc_toolchain_impl_" + case,
            toolchain_type = "@rules_cc//cc:toolchain_type",
        )

    # A platform no C++ toolchain is registered for.
    native.platform(
        name = "no_cc_toolchain",
        constraint_values = ["@platforms//cpu:wasm32", "@platforms//os:none"],
    )

    _probe(
        name = "probe",
        libc = select({
            "//rust/private/libc:glibc": "glibc",
            "//rust/private/libc:musl": "musl",
            "//conditions:default": "default",
        }),
    )

    # The version suffix is stripped, as `@rules_cc//cc/libc` does.
    glibc_versioned_test(name = "glibc_versioned_test", expected = "glibc", target_under_test = ":probe")
    musl_test(name = "musl_test", expected = "musl", target_under_test = ":probe")

    # A toolchain which does not say, and no toolchain at all, select nothing.
    local_test(name = "local_test", expected = "default", target_under_test = ":probe")
    no_cc_toolchain_test(name = "no_cc_toolchain_test", expected = "default", target_under_test = ":probe")

    native.test_suite(
        name = name,
        tests = [
            ":glibc_versioned_test",
            ":musl_test",
            ":local_test",
            ":no_cc_toolchain_test",
        ],
    )
