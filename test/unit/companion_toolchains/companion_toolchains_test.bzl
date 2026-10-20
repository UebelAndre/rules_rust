"""Tests that rustdoc and clippy come from their own toolchains.

`rust_toolchain` carries only what every compile action needs. `rustdoc` and
`clippy-driver` are provided by the `rustdoc_toolchain` and `clippy_toolchain`
registered alongside it, each laying out `bin/<tool>` next to the
`librustc_driver` libraries the tool loads, and they are inputs only of the
actions which run them.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//rust:defs.bzl", "rust_clippy_aspect", "rust_doc", "rust_library")

_RUSTDOC = ["rustdoc", "rustdoc.exe"]
_CLIPPY = ["clippy-driver", "clippy-driver.exe", "cargo-clippy", "cargo-clippy.exe"]

def _find_action(actions, mnemonic):
    for action in actions:
        if action.mnemonic == mnemonic:
            return action
    fail("Failed to find {} action".format(mnemonic))

def _assert_no_inputs_named(env, action, names):
    for file in action.inputs.to_list():
        asserts.false(
            env,
            file.basename in names,
            "{} action should not depend on {}".format(action.mnemonic, file.path),
        )

def _assert_tool_from_own_toolchain(env, action, names):
    """Assert `action` runs a tool laid out as `<toolchain>/bin/<tool>` beside its `librustc_driver`."""
    inputs = action.inputs.to_list()
    tools = [file for file in inputs if file.basename in names]
    asserts.equals(env, 1, len(tools), "Expected exactly one of {} among the inputs of {}".format(names, action.mnemonic))
    if len(tools) != 1:
        return
    tool = tools[0]

    asserts.true(env, tool.dirname.endswith("/bin"), "{} should live in a `bin` directory".format(tool.path))
    asserts.false(env, "/rust_toolchain/" in tool.path, "{} should not come from the `rust_toolchain` sysroot".format(tool.path))

    root = tool.dirname.removesuffix("/bin")
    driver_libs = [
        file
        for file in inputs
        if file.path.startswith(root + "/") and "rustc_driver" in file.basename
    ]
    asserts.true(env, bool(driver_libs), "{} should be accompanied by `librustc_driver` under {}".format(tool.path, root))

def _rustc_excludes_companion_tools_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    action = _find_action(target.actions, "Rustc")
    _assert_no_inputs_named(env, action, _RUSTDOC + _CLIPPY)
    return analysistest.end(env)

rustc_excludes_companion_tools_test = analysistest.make(
    _rustc_excludes_companion_tools_test_impl,
)

def _clippy_uses_clippy_toolchain_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    action = _find_action(target.actions, "Clippy")
    _assert_tool_from_own_toolchain(env, action, ["clippy-driver", "clippy-driver.exe"])
    _assert_no_inputs_named(env, action, _RUSTDOC)
    return analysistest.end(env)

clippy_uses_clippy_toolchain_test = analysistest.make(
    _clippy_uses_clippy_toolchain_test_impl,
    extra_target_under_test_aspects = [rust_clippy_aspect],
)

def _rustdoc_uses_rustdoc_toolchain_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    action = _find_action(target.actions, "Rustdoc")
    _assert_tool_from_own_toolchain(env, action, _RUSTDOC)
    _assert_no_inputs_named(env, action, _CLIPPY)
    return analysistest.end(env)

rustdoc_uses_rustdoc_toolchain_test = analysistest.make(
    _rustdoc_uses_rustdoc_toolchain_test_impl,
)

def companion_toolchains_test_suite(name):
    """Entry-point macro called from the BUILD file.

    Args:
        name (str): The name of the test suite.
    """
    rust_library(
        name = "lib",
        srcs = ["lib.rs"],
        crate_name = "companion_toolchains",
        edition = "2021",
    )

    rust_doc(
        name = "lib_doc",
        crate = ":lib",
    )

    rustc_excludes_companion_tools_test(
        name = "rustc_excludes_companion_tools_test",
        target_under_test = ":lib",
    )

    clippy_uses_clippy_toolchain_test(
        name = "clippy_uses_clippy_toolchain_test",
        target_under_test = ":lib",
    )

    rustdoc_uses_rustdoc_toolchain_test(
        name = "rustdoc_uses_rustdoc_toolchain_test",
        target_under_test = ":lib_doc",
    )

    native.test_suite(
        name = name,
        tests = [
            ":rustc_excludes_companion_tools_test",
            ":clippy_uses_clippy_toolchain_test",
            ":rustdoc_uses_rustdoc_toolchain_test",
        ],
    )
