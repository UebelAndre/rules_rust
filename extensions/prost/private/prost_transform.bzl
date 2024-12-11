"""Prost rules."""

load("@rules_rust//rust:defs.bzl", "rust_common")

ProstTransformInfo = provider(
    doc = "Info about transformations to apply to Prost generated source code.",
    fields = {
        "deps": "Depset[CrateInfo]: Additional dependencies to compile into the Prost target.",
        "prost_opts": "List[str]: Additional prost flags.",
        "srcs": "Depset[File]: Additional source files to include in generated Prost source code.",
        "tonic_opts": "List[str]: Additional tonic flags.",
    },
)

def _rust_prost_transform_impl(ctx):
    deps = []
    for target in ctx.attr.deps:
        if rust_common.crate_info in target:
            deps.append(target[rust_common.crate_info])
        if rust_common.crate_group_info in target:
            deps.append(target[rust_common.crate_group_info])

    return [ProstTransformInfo(
        deps = ctx.attr.deps,
        prost_opts = ctx.attr.prost_opts,
        srcs = depset(ctx.files.srcs),
        tonic_opts = ctx.attr.tonic_opts,
    )]

rust_prost_transform = rule(
    doc = "A rule for transforming the outputs of `ProstGenProto` actions.",
    implementation = _rust_prost_transform_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "Additional dependencies to add to the compiled crate.",
            providers = [[rust_common.crate_info], [rust_common.crate_group_info]],
        ),
        "prost_opts": attr.string_list(
            doc = "Additional options to add to Prost.",
        ),
        "srcs": attr.label_list(
            doc = "Additional source files to include in generated Prost source code.",
            allow_files = True,
        ),
        "tonic_opts": attr.string_list(
            doc = "Additional options to add to Tonic.",
        ),
    },
)
