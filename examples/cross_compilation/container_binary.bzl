load("@rules_rust//rust:defs.bzl", "rust_common")

def _platform_transition(settings, attrs):
    _ignore = (settings)
    return {"//command_line_option:platforms": attrs.platform}

platform_transition = transition(
    implementation = _platform_transition,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _container_binary_impl(ctx):
    return [DefaultInfo(
        files = ctx.executable.crate,
        runfiles = ctx.runfiles(transitive_files = ctx.attr.crate[DefaultInfo].default_runfiles),
    )]

rust_container_binary = rule(
    doc = "",
    implementation = _container_binary_impl,
    attrs = {
        "crate": attr.label(
            doc = "",
            cfg = platform_transition,
            executable = True,
            providers = [rust_common.crate_info],
        ),
        "platform": attr.string(
            doc = "",
            values = ["@rules_rust//rust/platform:x86_64-unknown-linux-gnu"],
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        ),
        "_cc_toolchain": attr.label(
            default = "@bazel_tools//tools/cpp:current_cc_toolchain",
        ),
    },
    fragments = ["cpp"],
    host_fragments = ["cpp"],
    toolchains = [
        "@bazel_tools//tools/cpp:toolchain_type",
    ],
    incompatible_use_toolchain_transition = True,
)
