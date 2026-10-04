"""Unit tests for coverage support."""

load("@bazel_features//:features.bzl", "bazel_features")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_CollectorInfo = provider(
    "The configured collector and expected execution platform output root.",
    fields = {"expected_root": "Output root for the test platform", "path": "Collector execution path"},
)

def _platform_marker_impl(ctx):
    marker = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(marker, "")
    return [DefaultInfo(files = depset([marker]))]

platform_marker = rule(implementation = _platform_marker_impl)

def _collector_probe_impl(ctx):
    # Forward only analysis information. Coverage must not build the fixture's
    # outputs on its synthetic execution platforms.
    return [
        _CollectorInfo(
            path = ctx.attr.dep[RunEnvironmentInfo].environment["CC_CODE_COVERAGE_SCRIPT"],
            expected_root = ctx.file.marker.root.path,
        ),
        DefaultInfo(files = depset()),
    ]

collector_probe = rule(
    implementation = _collector_probe_impl,
    attrs = {
        "dep": attr.label(providers = [RunEnvironmentInfo]),
        "marker": attr.label(allow_single_file = True, cfg = "exec"),
    },
)

def _collector_platform_test_impl(ctx):
    env = analysistest.begin(ctx)
    collector = analysistest.target_under_test(env)[_CollectorInfo]
    asserts.true(env, collector.path.startswith(collector.expected_root + "/"), "Coverage collector must use the test execution platform: " + collector.path + " (expected " + collector.expected_root + ")")
    return analysistest.end(env)

collector_platform_test = analysistest.make(
    _collector_platform_test_impl,
    config_settings = {
        "//command_line_option:collect_code_coverage": True,
        "//command_line_option:extra_execution_platforms": [
            str(Label(":compiler_platform")),
            str(Label(":test_platform")),
        ],
        "//command_line_option:platforms": str(Label(":test_platform")),
        "//command_line_option:use_target_platform_for_tests": False,
        # Inspect the collector without requesting the synthetic fixture's
        # executable and tools as coverage report metadata.
        str(Label("//rust/settings:experimental_use_coverage_metadata_files")): False,
    } | ({
        str(Label("@bazel_tools//tools/test:incompatible_use_default_test_toolchain")): True,
    } if bazel_features.toolchains.has_default_test_toolchain_type else {}),
)

def _profiler_runtime_libraries(tut):
    """Collect the `profiler_builtins` archives linked through a target's `CcInfo`."""
    libraries = []
    for linker_input in tut[CcInfo].linking_context.linker_inputs.to_list():
        for library in linker_input.libraries:
            archive = library.static_library or library.pic_static_library
            if archive and "profiler_builtins" in archive.basename:
                libraries.append(archive)
    return libraries

def _assert_profiler_runtime(env, tut, expected_runtime):
    asserts.equals(
        env,
        1 if expected_runtime else 0,
        len(_profiler_runtime_libraries(tut)),
        "The LLVM profile runtime must be linked exactly when the archive contains instrumented Rust",
    )

def _staticlib_links_profiler_runtime_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_profiler_runtime(env, analysistest.target_under_test(env), expected_runtime = True)
    return analysistest.end(env)

def _staticlib_without_coverage_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_profiler_runtime(env, analysistest.target_under_test(env), expected_runtime = False)
    return analysistest.end(env)

def _uninstrumented_staticlib_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_profiler_runtime(env, analysistest.target_under_test(env), expected_runtime = False)
    return analysistest.end(env)

def _staticlib_with_instrumented_dep_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The archive itself is outside the filter, but it bundles an instrumented
    # direct dependency, so the runtime is still required.
    _assert_profiler_runtime(env, analysistest.target_under_test(env), expected_runtime = True)
    return analysistest.end(env)

def _staticlib_with_only_transitive_instrumented_dep_test_impl(ctx):
    env = analysistest.begin(ctx)

    # Known limitation: Bazel only reports instrumentation for direct
    # dependencies, so an archive whose only instrumented crate is transitive
    # keeps relying on the consumer's toolchain runtime, as it did before.
    _assert_profiler_runtime(env, analysistest.target_under_test(env), expected_runtime = False)
    return analysistest.end(env)

def _dylib_does_not_duplicate_profiler_runtime_test_impl(ctx):
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)

    # `rustc` links a `dylib` itself and already includes `profiler_builtins`,
    # so a second copy must not be handed to C/C++ consumers.
    _assert_profiler_runtime(env, tut, expected_runtime = False)
    return analysistest.end(env)

dylib_does_not_duplicate_profiler_runtime_test = analysistest.make(
    _dylib_does_not_duplicate_profiler_runtime_test_impl,
    config_settings = {
        "//command_line_option:collect_code_coverage": True,
    },
)

# Instrumented under coverage with the default `--instrumentation_filter`.
staticlib_links_profiler_runtime_test = analysistest.make(
    _staticlib_links_profiler_runtime_test_impl,
    config_settings = {
        "//command_line_option:collect_code_coverage": True,
    },
)

# A regular build never links the runtime. Pinned explicitly so the test keeps
# its meaning when the suite itself runs under `bazel coverage`.
staticlib_without_coverage_test = analysistest.make(
    _staticlib_without_coverage_test_impl,
    config_settings = {
        "//command_line_option:collect_code_coverage": False,
    },
)

# Coverage is on, but nothing in the archive is instrumented, so injecting a
# runtime would only risk mixing it with the consumer's own profile runtime.
uninstrumented_staticlib_test = analysistest.make(
    _uninstrumented_staticlib_test_impl,
    config_settings = {
        "//command_line_option:collect_code_coverage": True,
        "//command_line_option:instrumentation_filter": "-//test/unit/coverage[/:]",
    },
)

# Only the dependency's package is instrumented.
staticlib_with_instrumented_dep_test = analysistest.make(
    _staticlib_with_instrumented_dep_test_impl,
    config_settings = {
        "//command_line_option:collect_code_coverage": True,
        "//command_line_option:instrumentation_filter": "//test/unit/coverage/instrumented_dep[/:]",
    },
)

staticlib_with_only_transitive_instrumented_dep_test = analysistest.make(
    _staticlib_with_only_transitive_instrumented_dep_test_impl,
    config_settings = {
        "//command_line_option:collect_code_coverage": True,
        "//command_line_option:instrumentation_filter": "//test/unit/coverage/instrumented_dep[/:]",
    },
)
