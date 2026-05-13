"""Unittest to verify properties of rustdoc merge mode"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//rust:defs.bzl", "rust_doc", "rust_library")
load(
    "//test/unit:common.bzl",
    "assert_argv_contains",
    "assert_argv_contains_prefix_not",
)

def _rustdoc_merge_requires_nightly_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "nightly")
    return analysistest.end(env)

rustdoc_merge_requires_nightly_test = analysistest.make(
    _rustdoc_merge_requires_nightly_test_impl,
    expect_failure = True,
)

def _rustdoc_no_merge_unchanged_test_impl(ctx):
    """Verify that rust_doc without merge still produces the expected Rustdoc action."""
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)

    actions = tut.actions
    has_rustdoc = False
    for action in actions:
        if action.mnemonic == "Rustdoc":
            has_rustdoc = True
            for arg in action.argv:
                asserts.false(
                    env,
                    arg == "--merge=finalize" or arg == "--merge=none",
                    "Unexpected merge flag in non-merge rustdoc action: {}".format(arg),
                )

    asserts.true(env, has_rustdoc, "Expected a Rustdoc action")
    return analysistest.end(env)

rustdoc_no_merge_unchanged_test = analysistest.make(_rustdoc_no_merge_unchanged_test_impl)

def _rustdoc_merge_finalize_test_impl(ctx):
    """Verify the RustdocMerge action has --merge=finalize and -Z unstable-options."""
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)

    has_merge = False
    for action in tut.actions:
        if action.mnemonic == "RustdocMerge":
            has_merge = True
            assert_argv_contains(env, action, "--merge=finalize")
            assert_argv_contains(env, action, "-Z")
            assert_argv_contains(env, action, "unstable-options")
            assert_argv_contains_prefix_not(env, action, "--merge=none")

    asserts.true(env, has_merge, "Expected a RustdocMerge action")
    return analysistest.end(env)

rustdoc_merge_finalize_test = analysistest.make(
    _rustdoc_merge_finalize_test_impl,
    config_settings = {
        str(Label("//rust/toolchain/channel:channel")): "nightly",
    },
)

def _rustdoc_merge_includes_dep_parts_test_impl(ctx):
    """Verify the RustdocMerge action includes --include-parts-dir for dependencies."""
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)

    has_merge = False
    for action in tut.actions:
        if action.mnemonic == "RustdocMerge":
            has_merge = True
            has_include_parts = False
            for arg in action.argv:
                if arg == "--include-parts-dir":
                    has_include_parts = True
            asserts.true(
                env,
                has_include_parts,
                "Expected --include-parts-dir in RustdocMerge action args",
            )

    asserts.true(env, has_merge, "Expected a RustdocMerge action")
    return analysistest.end(env)

rustdoc_merge_includes_dep_parts_test = analysistest.make(
    _rustdoc_merge_includes_dep_parts_test_impl,
    config_settings = {
        str(Label("//rust/toolchain/channel:channel")): "nightly",
    },
)

def _rustdoc_parts_aspect_test_impl(ctx):
    """Verify the RustdocMerge action includes --include-parts-dir pointing to aspect outputs."""
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)

    has_merge = False
    for action in tut.actions:
        if action.mnemonic == "RustdocMerge":
            has_merge = True
            has_parts_out_dir = False
            for arg in action.argv:
                if ".rustdoc_parts.parts" in arg:
                    has_parts_out_dir = True
            asserts.true(
                env,
                has_parts_out_dir,
                "Expected --include-parts-dir referencing .rustdoc_parts.parts in RustdocMerge args: {}".format(
                    action.argv,
                ),
            )

    asserts.true(env, has_merge, "Expected a RustdocMerge action")
    return analysistest.end(env)

rustdoc_parts_aspect_test = analysistest.make(
    _rustdoc_parts_aspect_test_impl,
    config_settings = {
        str(Label("//rust/toolchain/channel:channel")): "nightly",
    },
)

NIGHTLY_ONLY = select({
    "@rules_rust//rust/toolchain/channel:nightly": [],
    "//conditions:default": ["@platforms//:incompatible"],
})

NOT_NIGHTLY = select({
    "@rules_rust//rust/toolchain/channel:nightly": ["@platforms//:incompatible"],
    "//conditions:default": [],
})

def _define_test_targets():
    rust_library(
        name = "merge_dep_lib",
        srcs = ["rustdoc_nodep_lib.rs"],
        edition = "2018",
    )

    rust_library(
        name = "merge_lib",
        srcs = ["rustdoc_lib.rs"],
        edition = "2018",
        deps = [":merge_dep_lib"],
    )

    rust_doc(
        name = "merge_doc",
        crate = ":merge_lib",
        merge = True,
        tags = ["manual"],
    )

    rust_doc(
        name = "no_merge_doc",
        crate = ":merge_lib",
    )

def rustdoc_merge_test_suite(name):
    """Entry-point macro called from the BUILD file.

    Args:
        name (str): Name of the macro.
    """

    _define_test_targets()

    rustdoc_merge_requires_nightly_test(
        name = "rustdoc_merge_requires_nightly_test",
        target_under_test = ":merge_doc",
        target_compatible_with = NOT_NIGHTLY,
    )

    rustdoc_no_merge_unchanged_test(
        name = "rustdoc_no_merge_unchanged_test",
        target_under_test = ":no_merge_doc",
    )

    rustdoc_merge_finalize_test(
        name = "rustdoc_merge_finalize_test",
        target_under_test = ":merge_doc",
        target_compatible_with = NIGHTLY_ONLY,
    )

    rustdoc_merge_includes_dep_parts_test(
        name = "rustdoc_merge_includes_dep_parts_test",
        target_under_test = ":merge_doc",
        target_compatible_with = NIGHTLY_ONLY,
    )

    rustdoc_parts_aspect_test(
        name = "rustdoc_parts_aspect_test",
        target_under_test = ":merge_doc",
        target_compatible_with = NIGHTLY_ONLY,
    )

    native.test_suite(
        name = name,
        tests = [
            ":rustdoc_merge_requires_nightly_test",
            ":rustdoc_no_merge_unchanged_test",
            ":rustdoc_merge_finalize_test",
            ":rustdoc_merge_includes_dep_parts_test",
            ":rustdoc_parts_aspect_test",
        ],
    )
