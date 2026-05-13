# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Rules for generating documentation with `rustdoc` for Bazel built crates"""

load("//rust/private:common.bzl", "rust_common")
load("//rust/private:providers.bzl", "LintsInfo")
load("//rust/private:rustc.bzl", "collect_deps", "collect_inputs", "construct_arguments")
load("//rust/private:utils.bzl", "dedent", "find_cc_toolchain", "find_toolchain")

RustDocPartsInfo = provider(
    doc = "Provider carrying rustdoc 'parts' data for cross-crate documentation merging.",
    fields = {
        "crate_name": "str: The name of the documented crate.",
        "doc_dir": "File: The per-crate documentation directory (from --merge=none).",
        "parts_dir": "File: The parts directory output (from --parts-out-dir).",
        "transitive_doc_dirs": "depset[File]: Doc dirs from this target's deps (not self).",
        "transitive_parts_dirs": "depset[File]: Parts dirs from this target's deps (not self).",
    },
)

def _strip_crate_info_output(crate_info):
    """Set the CrateInfo.output to None for a given CrateInfo provider.

    Args:
        crate_info (CrateInfo): A provider

    Returns:
        CrateInfo: A modified CrateInfo provider
    """
    return rust_common.create_crate_info(
        name = crate_info.name,
        type = crate_info.type,
        root = crate_info.root,
        srcs = crate_info.srcs,
        deps = crate_info.deps,
        proc_macro_deps = crate_info.proc_macro_deps,
        aliases = crate_info.aliases,
        # This crate info should have no output
        output = None,
        metadata = None,
        edition = crate_info.edition,
        rustc_env = crate_info.rustc_env,
        rustc_env_files = crate_info.rustc_env_files,
        is_test = crate_info.is_test,
        compile_data = crate_info.compile_data,
        compile_data_targets = crate_info.compile_data_targets,
        data = crate_info.data,
    )

def rustdoc_compile_action(
        ctx,
        toolchain,
        crate_info,
        lints_info = None,
        output = None,
        rustdoc_flags = [],
        is_test = False):
    """Create a struct of information needed for a `rustdoc` compile action based on crate passed to the rustdoc rule.

    Args:
        ctx (ctx): The rule's context object.
        toolchain (rust_toolchain): The currently configured `rust_toolchain`.
        crate_info (CrateInfo): The provider of the crate passed to a rustdoc rule.
        lints_info (LintsInfo, optional): The LintsInfo provider of the crate passed to the rustdoc rule.
        output (File, optional): An optional output a `rustdoc` action is intended to produce.
        rustdoc_flags (list, optional): A list of `rustdoc` specific flags.
        is_test (bool, optional): If True, the action will be configured for `rust_doc_test` targets

    Returns:
        struct: A struct of some `ctx.actions.run` arguments.
    """

    # If an output was provided, ensure it's used in rustdoc arguments
    if output:
        rustdoc_flags = [
            "--output",
            output.path,
        ] + rustdoc_flags

    # Specify rustc flags for lints, if they were provided.
    lint_files = []
    if lints_info:
        rustdoc_flags = rustdoc_flags + lints_info.rustdoc_lint_flags
        lint_files = lint_files + lints_info.rustdoc_lint_files

    # Collect HTML customization files
    html_input_files = []
    if hasattr(ctx.file, "html_in_header") and ctx.file.html_in_header:
        html_input_files.append(ctx.file.html_in_header)
    if hasattr(ctx.file, "html_before_content") and ctx.file.html_before_content:
        html_input_files.append(ctx.file.html_before_content)
    if hasattr(ctx.file, "html_after_content") and ctx.file.html_after_content:
        html_input_files.append(ctx.file.html_after_content)
    if hasattr(ctx.files, "markdown_css"):
        html_input_files.extend(ctx.files.markdown_css)

    cc_toolchain, feature_configuration = find_cc_toolchain(ctx)

    dep_info, build_info, _ = collect_deps(
        deps = crate_info.deps.to_list(),
        proc_macro_deps = crate_info.proc_macro_deps.to_list(),
        aliases = crate_info.aliases,
    )

    compile_inputs, out_dir, build_env_files, build_flags_files, linkstamp_outs, ambiguous_libs = collect_inputs(
        ctx = ctx,
        file = ctx.file,
        files = ctx.files,
        linkstamps = depset([]),
        toolchain = toolchain,
        cc_toolchain = cc_toolchain,
        feature_configuration = feature_configuration,
        crate_info = crate_info,
        dep_info = dep_info,
        build_info = build_info,
        lint_files = lint_files,
        # If this is a rustdoc test, we need to depend on rlibs rather than .rmeta.
        force_depend_on_objects = is_test,
        include_link_flags = False,
    )

    # Since this crate is not actually producing the output described by the
    # given CrateInfo, this attribute needs to be stripped to allow the rest
    # of the rustc functionality in `construct_arguments` to avoid generating
    # arguments expecting to do so.
    rustdoc_crate_info = _strip_crate_info_output(crate_info)

    args, env = construct_arguments(
        ctx = ctx,
        attr = ctx.attr,
        file = ctx.file,
        toolchain = toolchain,
        tool_path = toolchain.rust_doc.short_path if is_test else toolchain.rust_doc.path,
        cc_toolchain = cc_toolchain,
        feature_configuration = feature_configuration,
        crate_info = rustdoc_crate_info,
        dep_info = dep_info,
        linkstamp_outs = linkstamp_outs,
        ambiguous_libs = ambiguous_libs,
        output_hash = None,
        rust_flags = rustdoc_flags,
        out_dir = out_dir,
        build_env_files = build_env_files,
        build_flags_files = build_flags_files,
        emit = [],
        remap_path_prefix = None,
        add_flags_for_binary = True,
        include_link_flags = False,
        force_depend_on_objects = is_test,
        skip_expanding_rustc_env = True,
    )

    # Because rustdoc tests compile tests outside of the sandbox, the sysroot
    # must be updated to the `short_path` equivalent as it will now be
    # a part of runfiles.
    if is_test:
        if "SYSROOT" in env:
            env.update({"SYSROOT": "${{pwd}}/{}".format(toolchain.sysroot_short_path)})
        if "OUT_DIR" in env:
            env.update({"OUT_DIR": "${{pwd}}/{}".format(build_info.out_dir.short_path)})

    # Create the combined inputs including HTML customization files
    all_inputs = depset([crate_info.output], transitive = [compile_inputs, depset(html_input_files)])

    return struct(
        executable = ctx.executable._process_wrapper,
        inputs = all_inputs,
        env = env,
        arguments = args.all,
        tools = [toolchain.rust_doc],
    )

def _zip_action(ctx, input_dir, output_zip, crate_label):
    """Creates an archive of the generated documentation from `rustdoc`

    Args:
        ctx (ctx): The `rust_doc` rule's context object
        input_dir (File): A directory containing the outputs from rustdoc
        output_zip (File): The location of the output archive containing generated documentation
        crate_label (Label): The label of the crate docs are being generated for.
    """
    args = ctx.actions.args()
    args.add(output_zip)
    args.add(ctx.bin_dir.path)
    args.add_all([input_dir], expand_directories = True)
    ctx.actions.run(
        executable = ctx.executable._dir_zipper,
        inputs = [input_dir],
        outputs = [output_zip],
        arguments = [args],
        mnemonic = "RustdocZip",
        progress_message = "Creating RustdocZip for {}".format(crate_label),
    )

def _get_rustdoc_ready_crate_info(target, aspect_ctx = None):
    """Check that a target is suitable for rustdoc parts generation and extract the CrateInfo.

    Args:
        target (Target): The target the aspect is running on.
        aspect_ctx (ctx, optional): The aspect's context object.

    Returns:
        CrateInfo, optional: A CrateInfo provider if rustdoc should run, or None.
    """
    if target.label.workspace_root.startswith("external"):
        return None

    if aspect_ctx:
        ignore_tags = ["no_rustdoc", "no_doc"]
        for tag in aspect_ctx.rule.attr.tags:
            if tag.replace("-", "_").lower() in ignore_tags:
                return None

    if rust_common.crate_info in target:
        return target[rust_common.crate_info]
    elif rust_common.test_crate_info in target:
        return target[rust_common.test_crate_info].crate
    else:
        return None

def _rustdoc_parts_aspect_impl(target, ctx):
    crate_info = _get_rustdoc_ready_crate_info(target, ctx)
    if not crate_info:
        return [RustDocPartsInfo(
            crate_name = "",
            doc_dir = None,
            parts_dir = None,
            transitive_doc_dirs = depset([]),
            transitive_parts_dirs = depset([]),
        )]

    toolchain = find_toolchain(ctx)

    doc_dir = ctx.actions.declare_directory("{}.rustdoc_parts.doc".format(target.label.name))
    parts_dir = ctx.actions.declare_directory("{}.rustdoc_parts.parts".format(target.label.name))

    rustdoc_flags = [
        "-Z",
        "unstable-options",
        "--merge=none",
        "--parts-out-dir",
        parts_dir.path,
        "--output",
        doc_dir.path,
        "--extern",
        "{}={}".format(crate_info.name, crate_info.output.path),
    ]

    dep_info, build_info, _ = collect_deps(
        deps = crate_info.deps.to_list(),
        proc_macro_deps = crate_info.proc_macro_deps.to_list(),
        aliases = crate_info.aliases,
    )

    compile_inputs, out_dir, build_env_files, build_flags_files, linkstamp_outs, ambiguous_libs = collect_inputs(
        ctx = ctx,
        file = ctx.rule.file,
        files = ctx.rule.files,
        linkstamps = depset([]),
        toolchain = toolchain,
        cc_toolchain = None,
        feature_configuration = None,
        crate_info = crate_info,
        dep_info = dep_info,
        build_info = build_info,
        lint_files = [],
        force_depend_on_objects = False,
        include_link_flags = False,
    )

    rustdoc_crate_info = _strip_crate_info_output(crate_info)

    args, env = construct_arguments(
        ctx = ctx,
        attr = ctx.rule.attr,
        file = ctx.file,
        toolchain = toolchain,
        tool_path = toolchain.rust_doc.path,
        cc_toolchain = None,
        feature_configuration = None,
        crate_info = rustdoc_crate_info,
        dep_info = dep_info,
        linkstamp_outs = linkstamp_outs,
        ambiguous_libs = ambiguous_libs,
        output_hash = None,
        rust_flags = rustdoc_flags,
        out_dir = out_dir,
        build_env_files = build_env_files,
        build_flags_files = build_flags_files,
        emit = [],
        remap_path_prefix = None,
        add_flags_for_binary = True,
        include_link_flags = False,
        force_depend_on_objects = False,
        skip_expanding_rustc_env = True,
    )

    all_inputs = depset([crate_info.output], transitive = [compile_inputs])

    ctx.actions.run(
        mnemonic = "RustdocParts",
        progress_message = "Generating Rustdoc parts for {}".format(target.label),
        outputs = [doc_dir, parts_dir],
        executable = ctx.executable._process_wrapper,
        inputs = all_inputs,
        env = env,
        arguments = args.all,
        tools = [toolchain.rust_doc],
        toolchain = Label("//rust:toolchain_type"),
    )

    # Collect transitive parts from dependencies (excluding self)
    dep_doc_dirs = []
    dep_parts_dirs = []
    for dep in ctx.rule.attr.deps + getattr(ctx.rule.attr, "proc_macro_deps", []):
        if RustDocPartsInfo in dep:
            info = dep[RustDocPartsInfo]
            if info.doc_dir:
                dep_doc_dirs.append(info.doc_dir)
            if info.parts_dir:
                dep_parts_dirs.append(info.parts_dir)
            dep_doc_dirs.extend(info.transitive_doc_dirs.to_list())
            dep_parts_dirs.extend(info.transitive_parts_dirs.to_list())

    return [RustDocPartsInfo(
        crate_name = crate_info.name,
        doc_dir = doc_dir,
        parts_dir = parts_dir,
        transitive_doc_dirs = depset(dep_doc_dirs),
        transitive_parts_dirs = depset(dep_parts_dirs),
    )]

_rustdoc_parts_aspect = aspect(
    implementation = _rustdoc_parts_aspect_impl,
    attr_aspects = ["deps", "proc_macro_deps"],
    attrs = {
        "_error_format": attr.label(
            default = Label("//rust/settings:error_format"),
        ),
        "_extra_rustc_flag": attr.label(
            default = Label("//rust/settings:extra_rustc_flag"),
        ),
        "_per_crate_rustc_flag": attr.label(
            default = Label("//rust/settings:experimental_per_crate_rustc_flag"),
        ),
        "_process_wrapper": attr.label(
            doc = "A process wrapper for running rustdoc on all platforms",
            default = Label("//util/process_wrapper"),
            executable = True,
            cfg = "exec",
        ),
    },
    fragments = ["cpp"],
    provides = [RustDocPartsInfo],
    required_providers = [
        [rust_common.crate_info],
        [rust_common.test_crate_info],
    ],
    toolchains = [
        str(Label("//rust:toolchain_type")),
    ],
)

def _collect_html_flags(ctx):
    """Collect HTML customization flags from rule attributes.

    Args:
        ctx (ctx): The rule's context object.

    Returns:
        list: A list of rustdoc flag strings.
    """
    flags = []
    if ctx.attr.html_in_header:
        flags.extend(["--html-in-header", ctx.file.html_in_header.path])
    if ctx.attr.html_before_content:
        flags.extend(["--html-before-content", ctx.file.html_before_content.path])
    if ctx.attr.html_after_content:
        flags.extend(["--html-after-content", ctx.file.html_after_content.path])
    for css_file in ctx.files.markdown_css:
        flags.extend(["--markdown-css", css_file.path])
    return flags

def _rust_doc_impl(ctx):
    """The implementation of the `rust_doc` rule

    Args:
        ctx (ctx): The rule's context object
    """

    if ctx.attr.rustc_flags:
        # buildifier: disable=print
        print("rustc_flags is deprecated in favor of `rustdoc_flags` for rustdoc targets. Please update {}".format(
            ctx.label,
        ))

    crate = ctx.attr.crate
    crate_info = crate[rust_common.crate_info]

    if ctx.attr.merge:
        return _rust_doc_merge_impl(ctx, crate, crate_info)

    lints_info = crate[LintsInfo] if LintsInfo in crate else None

    output_dir = ctx.actions.declare_directory("{}.rustdoc".format(ctx.label.name))

    rustdoc_flags = [
        "--extern",
        "{}={}".format(crate_info.name, crate_info.output.path),
    ]
    rustdoc_flags.extend(_collect_html_flags(ctx))
    rustdoc_flags.extend(ctx.attr.rustdoc_flags)

    action = rustdoc_compile_action(
        ctx = ctx,
        toolchain = find_toolchain(ctx),
        crate_info = crate_info,
        lints_info = lints_info,
        output = output_dir,
        rustdoc_flags = rustdoc_flags,
    )

    ctx.actions.run(
        mnemonic = "Rustdoc",
        progress_message = "Generating Rustdoc for {}".format(crate.label),
        outputs = [output_dir],
        executable = action.executable,
        inputs = action.inputs,
        env = action.env,
        arguments = action.arguments,
        tools = action.tools,
        toolchain = Label("//rust:toolchain_type"),
    )

    # This rule does nothing without a single-file output, though the directory should've sufficed.
    _zip_action(ctx, output_dir, ctx.outputs.rust_doc_zip, crate.label)

    return [
        DefaultInfo(
            files = depset([output_dir]),
        ),
        OutputGroupInfo(
            rustdoc_dir = depset([output_dir]),
            rustdoc_zip = depset([ctx.outputs.rust_doc_zip]),
        ),
    ]

def _rust_doc_merge_impl(ctx, crate, crate_info):
    """Implementation of rust_doc when merge = True.

    Generates merged documentation for the anchor crate and all its transitive
    Rust dependencies using rustdoc's --merge=finalize workflow.

    Args:
        ctx (ctx): The rule's context object.
        crate (Target): The anchor crate target.
        crate_info (CrateInfo): The anchor crate's CrateInfo provider.
    """
    toolchain = find_toolchain(ctx)

    if toolchain.channel != "nightly":
        fail(
            "rust_doc with merge = True requires a nightly Rust toolchain. " +
            "The current toolchain channel is '{}'. ".format(toolchain.channel) +
            "Configure a nightly toolchain to use cross-crate documentation merging.",
        )

    lints_info = crate[LintsInfo] if LintsInfo in crate else None
    output_dir = ctx.actions.declare_directory("{}.rustdoc".format(ctx.label.name))

    # Collect transitive parts from the aspect (deps only, not the anchor crate
    # itself -- the finalize step generates the anchor's docs and parts).
    all_doc_dirs = []
    all_parts_dirs = []
    if RustDocPartsInfo in crate:
        parts_info = crate[RustDocPartsInfo]
        all_doc_dirs.extend(parts_info.transitive_doc_dirs.to_list())
        all_parts_dirs.extend(parts_info.transitive_parts_dirs.to_list())

    # Build the finalize rustdoc flags for the anchor crate
    rustdoc_flags = [
        "-Z",
        "unstable-options",
        "--merge=finalize",
        "--extern",
        "{}={}".format(crate_info.name, crate_info.output.path),
    ]
    for parts_dir in all_parts_dirs:
        rustdoc_flags.extend(["--include-parts-dir", parts_dir.path])
    rustdoc_flags.extend(_collect_html_flags(ctx))
    rustdoc_flags.extend(ctx.attr.rustdoc_flags)

    action = rustdoc_compile_action(
        ctx = ctx,
        toolchain = toolchain,
        crate_info = crate_info,
        lints_info = lints_info,
        output = output_dir,
        rustdoc_flags = rustdoc_flags,
    )

    # Build the merger's own arguments before the separator
    merger_args = ctx.actions.args()
    merger_args.add("--output-dir", output_dir.path)
    for d in all_doc_dirs:
        merger_args.add("--doc-dir", d.path)
    merger_args.add("--")
    merger_args.add(action.executable.path)

    # The merge action needs all parts dirs and doc dirs as inputs
    merge_inputs = depset(
        all_doc_dirs + all_parts_dirs,
        transitive = [action.inputs],
    )

    ctx.actions.run(
        mnemonic = "RustdocMerge",
        progress_message = "Generating merged Rustdoc for {}".format(crate.label),
        outputs = [output_dir],
        executable = ctx.executable._doc_merger,
        inputs = merge_inputs,
        env = action.env,
        arguments = [merger_args] + action.arguments,
        tools = action.tools + [action.executable],
        toolchain = Label("//rust:toolchain_type"),
    )

    _zip_action(ctx, output_dir, ctx.outputs.rust_doc_zip, crate.label)

    return [
        DefaultInfo(
            files = depset([output_dir]),
        ),
        OutputGroupInfo(
            rustdoc_dir = depset([output_dir]),
            rustdoc_zip = depset([ctx.outputs.rust_doc_zip]),
        ),
    ]

rust_doc = rule(
    doc = dedent("""\
    Generates code documentation.

    Example:
    Suppose you have the following directory structure for a Rust library crate:

    ```
    [workspace]/
        WORKSPACE
        hello_lib/
            BUILD
            src/
                lib.rs
    ```

    To build [`rustdoc`][rustdoc] documentation for the `hello_lib` crate, define \
    a `rust_doc` rule that depends on the the `hello_lib` `rust_library` target:

    [rustdoc]: https://doc.rust-lang.org/book/documentation.html

    ```python
    package(default_visibility = ["//visibility:public"])

    load("@rules_rust//rust:defs.bzl", "rust_library", "rust_doc")

    rust_library(
        name = "hello_lib",
        srcs = ["src/lib.rs"],
    )

    rust_doc(
        name = "hello_lib_doc",
        crate = ":hello_lib",
    )
    ```

    Running `bazel build //hello_lib:hello_lib_doc` will build a zip file containing \
    the documentation for the `hello_lib` library crate generated by `rustdoc`.
    """),
    implementation = _rust_doc_impl,
    attrs = {
        "crate": attr.label(
            doc = (
                "The label of the target to generate code documentation for.\n" +
                "\n" +
                "`rust_doc` can generate HTML code documentation for the source files of " +
                "`rust_library` or `rust_binary` targets."
            ),
            providers = [rust_common.crate_info],
            mandatory = True,
            aspects = [_rustdoc_parts_aspect],
        ),
        "crate_features": attr.string_list(
            doc = dedent("""\
                List of features to enable for the crate being documented.
            """),
        ),
        "html_after_content": attr.label(
            doc = "File to add in `<body>`, after content.",
            allow_single_file = [".html", ".md"],
        ),
        "html_before_content": attr.label(
            doc = "File to add in `<body>`, before content.",
            allow_single_file = [".html", ".md"],
        ),
        "html_in_header": attr.label(
            doc = "File to add to `<head>`.",
            allow_single_file = [".html", ".md"],
        ),
        "markdown_css": attr.label_list(
            doc = "CSS files to include via `<link>` in a rendered Markdown file.",
            allow_files = [".css"],
        ),
        "merge": attr.bool(
            doc = dedent("""\
                When True, generates merged documentation for the crate and all its \
                transitive Rust dependencies with cross-crate linking, similar to \
                `cargo doc`. Requires a nightly Rust toolchain.

                The `crate` attribute specifies the anchor crate. All transitive Rust \
                dependencies are automatically documented and merged into the output.

                Example:
                ```python
                rust_doc(
                    name = "project_docs",
                    crate = ":my_lib",
                    merge = True,
                )
                ```
            """),
            default = False,
        ),
        "rustc_flags": attr.string_list(
            doc = "**Deprecated**: use `rustdoc_flags` instead",
        ),
        "rustdoc_flags": attr.string_list(
            doc = dedent("""\
                List of flags passed to `rustdoc`.

                These strings are subject to Make variable expansion for predefined
                source/output path variables like `$location`, `$execpath`, and
                `$rootpath`. This expansion is useful if you wish to pass a generated
                file of arguments to rustc: `@$(location //package:target)`.
            """),
        ),
        "_dir_zipper": attr.label(
            doc = "A tool that orchestrates the creation of zip archives for rustdoc outputs.",
            default = Label("//rust/private/rustdoc/dir_zipper"),
            cfg = "exec",
            executable = True,
        ),
        "_doc_merger": attr.label(
            doc = "A tool that merges rustdoc outputs from multiple crates.",
            default = Label("//rust/private/rustdoc/doc_merger"),
            cfg = "exec",
            executable = True,
        ),
        "_error_format": attr.label(
            default = Label("//rust/settings:error_format"),
        ),
        "_process_wrapper": attr.label(
            doc = "A process wrapper for running rustdoc on all platforms",
            default = Label("@rules_rust//util/process_wrapper"),
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
    },
    fragments = ["cpp"],
    outputs = {
        "rust_doc_zip": "%{name}.zip",
    },
    toolchains = [
        str(Label("//rust:toolchain_type")),
        config_common.toolchain_type("@bazel_tools//tools/cpp:toolchain_type", mandatory = False),
    ],
)
