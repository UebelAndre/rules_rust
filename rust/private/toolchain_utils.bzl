"""A module defining toolchain utilities"""

def _toolchain_files_impl(ctx):
    toolchain = ctx.toolchains[str(Label("//rust:toolchain_type"))]

    runfiles = None
    if ctx.attr.tool == "cargo":
        files = depset([toolchain.cargo])
        runfiles = ctx.runfiles(
            files = [
                toolchain.cargo,
                toolchain.rustc,
            ],
            transitive_files = toolchain.rustc_lib,
        )
    elif ctx.attr.tool == "cargo-clippy":
        files = depset([toolchain.cargo_clippy])
        runfiles = ctx.runfiles(
            files = [
                toolchain.cargo_clippy,
                toolchain.clippy_driver,
                toolchain.rustc,
            ],
            transitive_files = toolchain.rustc_lib,
        )
    elif ctx.attr.tool == "clippy":
        files = depset([toolchain.clippy_driver])
        runfiles = ctx.runfiles(
            files = [
                toolchain.clippy_driver,
                toolchain.rustc,
            ],
            transitive_files = toolchain.rustc_lib,
        )
    elif ctx.attr.tool == "rustc":
        files = depset([toolchain.rustc])
        runfiles = ctx.runfiles(
            files = [toolchain.rustc],
            transitive_files = toolchain.rustc_lib,
        )
    elif ctx.attr.tool == "rustdoc":
        files = depset([toolchain.rust_doc])
        runfiles = ctx.runfiles(
            files = [toolchain.rust_doc],
            transitive_files = toolchain.rustc_lib,
        )
    elif ctx.attr.tool == "rustfmt":
        files = depset([toolchain.rustfmt])
        runfiles = ctx.runfiles(
            files = [toolchain.rustfmt],
            transitive_files = toolchain.rustc_lib,
        )
    elif ctx.attr.tool == "rustc_lib":
        files = toolchain.rustc_lib
    elif ctx.attr.tool == "rust_std" or ctx.attr.tool == "rust_stdlib" or ctx.attr.tool == "rust_lib":
        files = toolchain.rust_std
    else:
        fail("Unsupported tool: ", ctx.attr.tool)

    return [DefaultInfo(
        files = files,
        runfiles = runfiles,
    )]

toolchain_files = rule(
    doc = "A rule for fetching files from a rust toolchain for the exec platform.",
    implementation = _toolchain_files_impl,
    attrs = {
        "tool": attr.string(
            doc = "The desired tool to get form the current rust_toolchain",
            values = [
                "cargo",
                "cargo-clippy",
                "clippy",
                "rust_lib",
                "rust_std",
                "rust_stdlib",
                "rustc_lib",
                "rustc",
                "rustdoc",
                "rustfmt",
            ],
            mandatory = True,
        ),
    },
    toolchains = [
        str(Label("//rust:toolchain_type")),
    ],
)

def _current_rust_toolchain_impl(ctx):
    toolchain = ctx.toolchains[str(Label("@rules_rust//rust:toolchain_type"))]

    return [
        toolchain,
        toolchain.make_variables,
        DefaultInfo(
            files = toolchain.all_files,
        ),
    ]

current_rust_toolchain = rule(
    doc = "A rule for exposing the current registered `rust_toolchain`.",
    implementation = _current_rust_toolchain_impl,
    toolchains = [
        str(Label("@rules_rust//rust:toolchain_type")),
    ],
)

def _transition_to_target_impl(settings, _attr):
    return {
        # String conversion is needed to prevent a crash with Bazel 6.x.
        "//command_line_option:extra_execution_platforms": [
            str(platform)
            for platform in settings["//command_line_option:platforms"]
        ],
    }

_transition_to_target = transition(
    implementation = _transition_to_target_impl,
    inputs = ["//command_line_option:platforms"],
    outputs = ["//command_line_option:extra_execution_platforms"],
)

def _toolchain_files_for_target_impl(ctx):
    return [ctx.attr.toolchain_files[0][DefaultInfo]]

toolchain_files_for_target = rule(
    doc = "A rule for fetching files from a rust toolchain for the target platform.",
    implementation = _toolchain_files_for_target_impl,
    attrs = {
        "toolchain_files": attr.label(cfg = _transition_to_target, mandatory = True),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def get_coverage_env(toolchain):
    """_summary_

    Args:
        toolchain (_type_): _description_

    Returns:
        _type_: _description_
    """
    env = {}
    if toolchain.llvm_cov:
        if not toolchain.llvm_profdata:
            fail("toolchain.llvm_profdata is required if toolchain.llvm_cov is set.")

        if toolchain._experimental_use_coverage_metadata_files:
            llvm_cov_path = toolchain.llvm_cov.path
            llvm_profdata_path = toolchain.llvm_profdata.path
        else:
            llvm_cov_path = toolchain.llvm_cov.short_path
            if llvm_cov_path.startswith("../"):
                llvm_cov_path = llvm_cov_path[len("../"):]

            llvm_profdata_path = toolchain.llvm_profdata.short_path
            if llvm_profdata_path.startswith("../"):
                llvm_profdata_path = llvm_profdata_path[len("../"):]

        env["RUST_LLVM_COV"] = llvm_cov_path
        env["RUST_LLVM_PROFDATA"] = llvm_profdata_path

    return env
