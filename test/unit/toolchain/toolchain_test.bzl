"""Unit tests for rust toolchains."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_rust_toolchain_test_target_json//:defs.bzl", "TARGET_JSON")
load("//rust:defs.bzl", "rust_lto_flag")
load("//rust:rust_common.bzl", "RustToolchainInfo")
load("//rust:toolchain.bzl", "rust_stdlib_filegroup", "rust_toolchain")
load("//rust/platform:triple.bzl", "triple")

# buildifier: disable=bzl-visibility
load("//rust/private:providers.bzl", "PROCESS_WRAPPER", "RUST_TOOLCHAIN_SETTINGS", "rust_toolchain_info_fields")

def _toolchain_specifies_target_triple_test_impl(ctx):
    env = analysistest.begin(ctx)
    toolchain_info = analysistest.target_under_test(env)[platform_common.ToolchainInfo]

    asserts.equals(env, None, toolchain_info.target_json)
    asserts.equals(env, "toolchain-test-triple", toolchain_info.target_flag_value)
    asserts.equals(env, triple("toolchain-test-triple"), toolchain_info.target_triple)
    asserts.equals(env, "toolchain", toolchain_info.target_arch)

    return analysistest.end(env)

def _toolchain_specifies_target_json_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    toolchain_info = target[platform_common.ToolchainInfo]

    asserts.equals(env, None, toolchain_info.target_triple)
    asserts.equals(env, "x86_64", toolchain_info.target_arch)

    # The specific name here is not as valuable as identifying that `target_json` is a json file
    expected_basename = "{}.target.json".format(target.label.name)
    asserts.equals(env, expected_basename, toolchain_info.target_json.basename)

    # The value is expected to be to a generated file in bazel-out.
    asserts.equals(env, "File", type(toolchain_info.target_flag_value))
    target_path = toolchain_info.target_flag_value.path
    asserts.true(env, target_path.startswith("bazel-out/"))
    asserts.true(env, target_path.endswith("/bin/{}/{}".format(ctx.label.package, expected_basename)))

    return analysistest.end(env)

def _toolchain_location_expands_linkflags_impl(ctx):
    env = analysistest.begin(ctx)
    toolchain_info = analysistest.target_under_test(env)[platform_common.ToolchainInfo]

    asserts.equals(
        env,
        "test:test/unit/toolchain/config.txt",
        toolchain_info.stdlib_linkflags.linking_context.linker_inputs.to_list()[0].user_link_flags[0],
    )
    asserts.equals(
        env,
        "test:sysroot=" + toolchain_info.sysroot,
        toolchain_info.stdlib_linkflags.linking_context.linker_inputs.to_list()[0].user_link_flags[1],
    )

    return analysistest.end(env)

def _toolchain_location_expands_extra_rustc_flags_impl(ctx):
    env = analysistest.begin(ctx)
    toolchain_info = analysistest.target_under_test(env)[platform_common.ToolchainInfo]

    asserts.equals(
        env,
        "extra_rustc_flags:test/unit/toolchain/config.txt",
        toolchain_info.extra_rustc_flags[0],
    )
    asserts.equals(
        env,
        "extra_rustc_flags:sysroot=" + toolchain_info.sysroot,
        toolchain_info.extra_rustc_flags[1],
    )

    return analysistest.end(env)

def _toolchain_uses_custom_lto_flag_test_impl(ctx):
    env = analysistest.begin(ctx)
    toolchain_info = analysistest.target_under_test(env)[platform_common.ToolchainInfo]

    asserts.equals(env, "fat", toolchain_info.lto.mode)

    return analysistest.end(env)

def _std_libs_support_srcs_outside_package_test_impl(ctx):
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)
    actions = analysistest.target_actions(env)

    symlinks = [a for a in actions if a.mnemonic == "Symlink"]
    asserts.equals(env, 2, len(symlinks))

    rlib_symlink = symlinks[0].outputs.to_list()[0]
    asserts.equals(env, tut.label.package + "/core.rlib", rlib_symlink.short_path)

    a_symlink = symlinks[1].outputs.to_list()[0]
    asserts.equals(env, tut.label.package + "/libcore.a", a_symlink.short_path)

    return analysistest.end(env)

def _toolchain_info_is_carried_by_toolchain_info_test_impl(ctx):
    """`rust_toolchain` returns a `RustToolchainInfo`, and its `ToolchainInfo` carries the same data.

    Rules outside `rules_rust` read the fields off
    `ctx.toolchains["@rules_rust//rust:toolchain_type"]`, so every field of the
    provider is on the `ToolchainInfo` too, with the provider itself as
    `rust_toolchain_info`.
    """
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    info = target[RustToolchainInfo]
    toolchain = target[platform_common.ToolchainInfo]
    asserts.equals(env, info, toolchain.rust_toolchain_info)
    for field, value in rust_toolchain_info_fields(info).items():
        asserts.true(env, hasattr(toolchain, field), "`ToolchainInfo` lacks `{}`".format(field))
        asserts.equals(env, value, getattr(toolchain, field, None), field)
    return analysistest.end(env)

def _toolchain_info_rejects_another_setting_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "only a rule whose `_codegen_units` is `")
    return analysistest.end(env)

def _toolchain_info_rejects_a_missing_setting_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "only a rule with the attribute `_no_std` (defaulting to `")
    return analysistest.end(env)

def _toolchain_info_rejects_the_wrong_process_wrapper_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "only a rule whose `_process_wrapper` is `")
    return analysistest.end(env)

# The targets these tests analyze fail in every configuration, so outside the
# tests they are incompatible rather than broken: `manual` keeps them out of
# wildcard builds, but `cquery` and `aquery` analyze them all the same. The
# tests flip this flag through their transition.
_NEGATIVE_TESTS_FLAG = Label("//test/unit/toolchain:negative_toolchain_tests")

def _construct_toolchain_info_impl(ctx):
    """A rule which is not `rust_toolchain` constructing a `RustToolchainInfo`."""
    return [RustToolchainInfo(ctx = ctx)]

def _construct_bootstrapping_toolchain_info_impl(ctx):
    """A rule claiming to carry the bootstrap shell script."""
    return [RustToolchainInfo(ctx = ctx, _bootstrapping = True)]

_PROCESS_WRAPPER_ATTRS = {
    "_process_wrapper": attr.label(
        default = PROCESS_WRAPPER,
        executable = True,
        cfg = "exec",
    ),
}

_toolchain_reading_another_setting = rule(
    implementation = _construct_toolchain_info_impl,
    attrs = {
        name: attr.label(default = setting)
        for name, setting in RUST_TOOLCHAIN_SETTINGS.items()
    } | _PROCESS_WRAPPER_ATTRS | {
        "_codegen_units": attr.label(default = Label("//rust/settings:pipelined_compilation")),
    },
)

_toolchain_bootstrapping_with_the_process_wrapper = rule(
    implementation = _construct_bootstrapping_toolchain_info_impl,
    attrs = {
        name: attr.label(default = setting)
        for name, setting in RUST_TOOLCHAIN_SETTINGS.items()
    } | _PROCESS_WRAPPER_ATTRS,
)

_toolchain_missing_a_setting = rule(
    implementation = _construct_toolchain_info_impl,
    attrs = {
        name: attr.label(default = setting)
        for name, setting in RUST_TOOLCHAIN_SETTINGS.items()
        if name != "_no_std"
    } | _PROCESS_WRAPPER_ATTRS,
)

toolchain_info_is_carried_by_toolchain_info_test = analysistest.make(_toolchain_info_is_carried_by_toolchain_info_test_impl)
toolchain_info_rejects_another_setting_test = analysistest.make(
    _toolchain_info_rejects_another_setting_test_impl,
    expect_failure = True,
    config_settings = {str(_NEGATIVE_TESTS_FLAG): True},
)
toolchain_info_rejects_a_missing_setting_test = analysistest.make(
    _toolchain_info_rejects_a_missing_setting_test_impl,
    expect_failure = True,
    config_settings = {str(_NEGATIVE_TESTS_FLAG): True},
)
toolchain_info_rejects_the_wrong_process_wrapper_test = analysistest.make(
    _toolchain_info_rejects_the_wrong_process_wrapper_test_impl,
    expect_failure = True,
    config_settings = {str(_NEGATIVE_TESTS_FLAG): True},
)

toolchain_specifies_target_triple_test = analysistest.make(_toolchain_specifies_target_triple_test_impl)
toolchain_specifies_target_json_test = analysistest.make(_toolchain_specifies_target_json_test_impl)
toolchain_location_expands_linkflags_test = analysistest.make(_toolchain_location_expands_linkflags_impl)
toolchain_location_expands_extra_rustc_flags_test = analysistest.make(_toolchain_location_expands_extra_rustc_flags_impl)
toolchain_uses_custom_lto_flag_test = analysistest.make(_toolchain_uses_custom_lto_flag_test_impl)
std_libs_support_srcs_outside_package_test = analysistest.make(_std_libs_support_srcs_outside_package_test_impl)

def _define_test_targets():
    bool_flag(
        name = _NEGATIVE_TESTS_FLAG.name,
        build_setting_default = False,
    )
    native.config_setting(
        name = "negative_toolchain_tests_enabled",
        flag_values = {str(_NEGATIVE_TESTS_FLAG): "True"},
    )
    negative_kwargs = {
        "tags": ["manual"],
        "target_compatible_with": select({
            ":negative_toolchain_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
    }
    _toolchain_reading_another_setting(
        name = "toolchain_reading_another_setting",
        **negative_kwargs
    )
    _toolchain_missing_a_setting(
        name = "toolchain_missing_a_setting",
        **negative_kwargs
    )
    _toolchain_bootstrapping_with_the_process_wrapper(
        name = "toolchain_bootstrapping_with_the_process_wrapper",
        **negative_kwargs
    )

    native.filegroup(
        name = "stdlib_srcs",
        srcs = ["config.txt"],
    )
    rust_stdlib_filegroup(
        name = "std_libs",
        srcs = [":stdlib_srcs"],
    )

    rust_stdlib_filegroup(
        name = "std_libs_with_srcs_outside_package",
        srcs = ["//test/unit/toolchain/subpackage:std_libs_srcs"],
    )

    native.filegroup(
        name = "target_json",
        srcs = ["toolchain-test-triple.json"],
    )

    write_file(
        name = "mock_rustc",
        out = "mock_rustc.exe",
        content = [],
        is_executable = True,
    )

    write_file(
        name = "mock_rust_lld",
        out = "mock_rust_lld.exe",
        content = [],
        is_executable = True,
    )

    write_file(
        name = "mock_rustdoc",
        out = "mock_rustdoc.exe",
        content = [],
        is_executable = True,
    )

    rust_toolchain(
        name = "rust_triple_toolchain",
        binary_ext = "",
        dylib_ext = ".so",
        exec_triple = "x86_64-unknown-none",
        rust_doc = ":mock_rustdoc",
        rust_std = ":std_libs",
        rustc = ":mock_rustc",
        linker = ":mock_rust_lld",
        staticlib_ext = ".a",
        stdlib_linkflags = [],
        target_triple = "toolchain-test-triple",
    )

    encoded_target_json = json.encode(TARGET_JSON)

    rust_toolchain(
        name = "rust_json_toolchain",
        binary_ext = "",
        dylib_ext = ".so",
        exec_triple = "x86_64-unknown-none",
        rust_doc = ":mock_rustdoc",
        rust_std = ":std_libs",
        rustc = ":mock_rustc",
        linker = ":mock_rust_lld",
        staticlib_ext = ".a",
        stdlib_linkflags = [],
        target_json = encoded_target_json,
    )

    rust_toolchain(
        name = "rust_inline_json_toolchain",
        binary_ext = "",
        dylib_ext = ".so",
        exec_triple = "x86_64-unknown-none",
        rust_doc = ":mock_rustdoc",
        rust_std = ":std_libs",
        rustc = ":mock_rustc",
        linker = ":mock_rust_lld",
        staticlib_ext = ".a",
        stdlib_linkflags = [],
        target_json = json.encode(
            {
                "arch": "x86_64",
                "env": "gnu",
                "llvm-target": "x86_64-unknown-linux-gnu",
                "target-family": ["unix"],
                "target-pointer-width": "64",
            },
        ),
    )

    rust_toolchain(
        name = "rust_location_expand_toolchain",
        binary_ext = "",
        dylib_ext = ".so",
        exec_triple = "x86_64-unknown-none",
        rust_doc = ":mock_rustdoc",
        rust_std = ":std_libs",
        rustc = ":mock_rustc",
        linker = ":mock_rust_lld",
        staticlib_ext = ".a",
        stdlib_linkflags = ["test:$(location :stdlib_srcs)", "test:sysroot=$(RUST_SYSROOT)"],
        extra_rustc_flags = ["extra_rustc_flags:$(location :stdlib_srcs)", "extra_rustc_flags:sysroot=$(RUST_SYSROOT)"],
        target_json = encoded_target_json,
    )

    rust_lto_flag(
        name = "fat_lto",
        build_setting_default = "fat",
    )

    rust_toolchain(
        name = "rust_custom_lto_toolchain",
        binary_ext = "",
        dylib_ext = ".so",
        exec_triple = "x86_64-unknown-none",
        lto = ":fat_lto",
        rust_doc = ":mock_rustdoc",
        rust_std = ":std_libs",
        rustc = ":mock_rustc",
        linker = ":mock_rust_lld",
        staticlib_ext = ".a",
        stdlib_linkflags = [],
        target_triple = "toolchain-test-triple",
    )

def toolchain_test_suite(name):
    """Entry-point macro called from the BUILD file.

    Args:
        name (str): The name of the test suite.
    """
    _define_test_targets()

    toolchain_info_is_carried_by_toolchain_info_test(
        name = "toolchain_info_is_carried_by_toolchain_info_test",
        target_under_test = ":rust_triple_toolchain",
    )
    toolchain_info_rejects_another_setting_test(
        name = "toolchain_info_rejects_another_setting_test",
        target_under_test = ":toolchain_reading_another_setting",
    )
    toolchain_info_rejects_a_missing_setting_test(
        name = "toolchain_info_rejects_a_missing_setting_test",
        target_under_test = ":toolchain_missing_a_setting",
    )
    toolchain_info_rejects_the_wrong_process_wrapper_test(
        name = "toolchain_info_rejects_the_wrong_process_wrapper_test",
        target_under_test = ":toolchain_bootstrapping_with_the_process_wrapper",
    )
    toolchain_specifies_target_triple_test(
        name = "toolchain_specifies_target_triple_test",
        target_under_test = ":rust_triple_toolchain",
    )
    toolchain_specifies_target_json_test(
        name = "toolchain_specifies_target_json_test",
        target_under_test = ":rust_json_toolchain",
    )
    toolchain_specifies_target_json_test(
        name = "toolchain_specifies_inline_target_json_test",
        target_under_test = ":rust_inline_json_toolchain",
    )
    toolchain_location_expands_linkflags_test(
        name = "toolchain_location_expands_linkflags_test",
        target_under_test = ":rust_location_expand_toolchain",
    )
    toolchain_location_expands_extra_rustc_flags_test(
        name = "toolchain_location_expands_extra_rustc_flags_test",
        target_under_test = ":rust_location_expand_toolchain",
    )
    toolchain_uses_custom_lto_flag_test(
        name = "toolchain_uses_custom_lto_flag_test",
        target_under_test = ":rust_custom_lto_toolchain",
    )
    std_libs_support_srcs_outside_package_test(
        name = "std_libs_support_srcs_outside_package_test",
        target_under_test = ":std_libs_with_srcs_outside_package",
    )

    native.test_suite(
        name = name,
        tests = [
            ":toolchain_info_is_carried_by_toolchain_info_test",
            ":toolchain_info_rejects_another_setting_test",
            ":toolchain_info_rejects_a_missing_setting_test",
            ":toolchain_info_rejects_the_wrong_process_wrapper_test",
            ":toolchain_specifies_target_triple_test",
            ":toolchain_specifies_target_json_test",
            ":toolchain_specifies_inline_target_json_test",
            ":toolchain_location_expands_linkflags_test",
            ":toolchain_location_expands_extra_rustc_flags_test",
            ":toolchain_uses_custom_lto_flag_test",
            ":std_libs_support_srcs_outside_package_test",
        ],
    )
