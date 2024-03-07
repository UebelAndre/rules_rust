"""Rules for ensuring Rust targets are depending on what they use"""

load("//rust:defs.bzl", "rust_common")

def _rust_deptree_aspect_impl(target, ctx):
    crates = {}
    all_deps = getattr(ctx.rule.attr, "deps", []) + getattr(ctx.rule.attr, "proc_macro_deps", [])
    for dep in all_deps:
        if rust_common.crate_info not in dep:
            continue
        crates[dep[rust_common.crate_info].owner] = dep[rust_common.crate_info].name

    aliases = target[rust_common.crate_info].aliases
    srcs = target[rust_common.crate_info].srcs

    manifest = ctx.actions.declare_file("{}.rust_deptree.manifest.json".format(target.label.name))
    ctx.actions.write(
        output = manifest,
        content = json.encode_indent(
            struct(
                crates = crates,
                aliases = aliases,
                srcs = srcs,
            ),
            indent = " " * 4,
        ),
    )

    output = ctx.actions.declare_file("{}.rust_deptree.ok".format(target.label.name))

    args = ctx.actions.args()
    args.add("--output", output)
    args.add("--manifest", manifest)

    ctx.actions.run(
        mnemonic = "RustDeps",
        outputs = [output],
        executable = ctx.executable._tester,
        arguments = [args],
        inputs = depset([manifest], transitive = [srcs]),
    )

    return [OutputGroupInfo(
        rust_deptree_check = depset([output]),
    )]

rust_deptree_aspect = aspect(
    doc = "TODO",
    implementation = _rust_deptree_aspect_impl,
    attrs = {
        "_tester": attr.label(
            doc = "TODO",
            executable = True,
            cfg = "exec",
            default = Label("//tools/deps/private:rust_deptree"),
        ),
    },
    required_providers = [rust_common.crate_info],
)
