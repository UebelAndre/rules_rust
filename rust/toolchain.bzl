"""The rust_toolchain rule definition and implementation."""

load(
    "//rust/private:utils.bzl",
    "dedent",
    "find_cc_toolchain",
)

def _make_dota(ctx, f):
    """Add a symlink for a file that ends in .a, so it can be used as a staticlib.

    Args:
        ctx (ctx): The rule's context object.
        f (File): The file to symlink.

    Returns:
        The symlink's File.
    """
    dot_a = ctx.actions.declare_file(f.basename + ".a", sibling = f)
    ctx.actions.symlink(output = dot_a, target_file = f)
    return dot_a

RustStdLibInfo = provider(
    doc = "",
    fields = {
        "alloc_files": "",
        "between_alloc_and_core_files": "",
        "between_core_and_std_files": "",
        "core_files": "",
        "dot_a_files": "Depset of Files",
        "srcs": "",
        "std_files": "Depset of Files",
        "std_rlibs": "",
    },
)

def _rust_stdlib_filegroup_impl(ctx):
    rust_lib = ctx.files.srcs
    std_rlibs = [f for f in rust_lib if f.basename.endswith(".rlib")]
    dot_a_files = []
    between_alloc_and_core_files = []
    core_files = []
    between_core_and_std_files = []
    std_files = []
    alloc_files = []
    if std_rlibs:
        # std depends on everything
        #
        # core only depends on alloc, but we poke adler in there
        # because that needs to be before miniz_oxide
        #
        # alloc depends on the allocator_library if it's configured, but we
        # do that later.
        dot_a_files = [_make_dota(ctx, f) for f in std_rlibs]

        alloc_files = [f for f in dot_a_files if "alloc" in f.basename and "std" not in f.basename]
        between_alloc_and_core_files = [f for f in dot_a_files if "compiler_builtins" in f.basename]
        core_files = [f for f in dot_a_files if ("core" in f.basename or "adler" in f.basename) and "std" not in f.basename]
        between_core_and_std_files = [
            f
            for f in dot_a_files
            if "alloc" not in f.basename and "compiler_builtins" not in f.basename and "core" not in f.basename and "adler" not in f.basename and "std" not in f.basename
        ]
        std_files = [f for f in dot_a_files if "std" in f.basename]

        partitioned_files_len = len(alloc_files) + len(between_alloc_and_core_files) + len(core_files) + len(between_core_and_std_files) + len(std_files)
        if partitioned_files_len != len(dot_a_files):
            partitioned = alloc_files + between_alloc_and_core_files + core_files + between_core_and_std_files + std_files
            for f in sorted(partitioned):
                # buildifier: disable=print
                print("File partitioned: {}".format(f.basename))
            fail("rust_toolchain couldn't properly partition rlibs in rust_lib. Partitioned {} out of {} files. This is probably a bug in the rule implementation.".format(partitioned_files_len, len(dot_a_files)))

    return [
        DefaultInfo(
            files = depset(ctx.files.srcs),
        ),
        RustStdLibInfo(
            std_rlibs = std_rlibs,
            dot_a_files = dot_a_files,
            between_alloc_and_core_files = between_alloc_and_core_files,
            core_files = core_files,
            between_core_and_std_files = between_core_and_std_files,
            std_files = std_files,
            alloc_files = alloc_files,
        ),
    ]

rust_stdlib_filegroup = rule(
    doc = dedent("""\

    """),
    implementation = _rust_stdlib_filegroup_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "",
            mandatory = True,
        ),
    },
)

def _ltl(library, ctx, cc_toolchain, feature_configuration):
    return cc_common.create_library_to_link(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        static_library = library,
        pic_static_library = library,
    )

def _make_libstd_and_allocator_ccinfo(ctx, rust_lib, allocator_library):
    """Make the CcInfo (if possible) for libstd and allocator libraries.

    Args:
        ctx (ctx): The rule's context object.
        rust_lib: The rust standard library.
        allocator_library: The target to use for providing allocator functions.


    Returns:
        A CcInfo object for the required libraries, or None if no such libraries are available.
    """
    cc_toolchain, feature_configuration = find_cc_toolchain(ctx)
    link_inputs = []
    rust_stdlib_info = ctx.attr.rust_stdlib[RustStdLibInfo]
    if rust_stdlib_info.std_rlibs:
        alloc_inputs = depset(
            [_ltl(f, ctx, cc_toolchain, feature_configuration) for f in rust_stdlib_info.alloc_files],
        )
        between_alloc_and_core_inputs = depset(
            [_ltl(f, ctx, cc_toolchain, feature_configuration) for f in rust_stdlib_info.between_alloc_and_core_files],
            transitive = [alloc_inputs],
            order = "topological",
        )
        core_inputs = depset(
            [_ltl(f, ctx, cc_toolchain, feature_configuration) for f in rust_stdlib_info.core_files],
            transitive = [between_alloc_and_core_inputs],
            order = "topological",
        )
        between_core_and_std_inputs = depset(
            [_ltl(f, ctx, cc_toolchain, feature_configuration) for f in rust_stdlib_info.between_core_and_std_files],
            transitive = [core_inputs],
            order = "topological",
        )
        std_inputs = depset(
            [_ltl(f, ctx, cc_toolchain, feature_configuration) for f in rust_stdlib_info.std_files],
            transitive = [between_core_and_std_inputs],
            order = "topological",
        )

        link_inputs.append(cc_common.create_linker_input(
            owner = rust_lib.label,
            libraries = std_inputs,
        ))

    allocator_inputs = None
    if allocator_library:
        allocator_inputs = [allocator_library[CcInfo].linking_context.linker_inputs]

    libstd_and_allocator_ccinfo = None
    if link_inputs:
        return CcInfo(linking_context = cc_common.create_linking_context(linker_inputs = depset(
            link_inputs,
            transitive = allocator_inputs,
            order = "topological",
        )))
    return None

def _rust_exec_toolchain_impl(ctx):
    """The rust_exec_toolchain implementation

    Args:
        ctx (ctx): The rule's context object

    Returns:
        list: A list containing the target's toolchain Provider info
    """

    toolchain = platform_common.ToolchainInfo(
        rustc = ctx.file.rustc,
        triple = ctx.attr.triple,
        os = ctx.attr.os,
        arch = ctx.attr.triple.split("-")[0],
        crosstool_files = ctx.files._crosstool,
        rustc_srcs = ctx.attr.rustc_srcs,
        rustc_lib = ctx.attr.rustc_lib,
        rustdoc = ctx.file.rustdoc,
    )
    return [toolchain]

rust_exec_toolchain = rule(
    doc = dedent("""\
    Declares a Rust exec/host toolchain for use.

    This is for declaring a custom toolchain, eg. for configuring a particular version of rust or supporting a new platform.

    Example:

    Suppose the core rust team has ported the compiler to a new target CPU, called `cpuX`. This \
    support can be used in Bazel by defining a new toolchain definition and declaration:

    ```python
    load('@rules_rust//rust:toolchain.bzl', 'rust_exec_toolchain')

    rust_exec_toolchain(
        name = "rust_cpuX_impl",
        # see attributes...
    )

    toolchain(
        name = "rust_cpuX",
        exec_compatible_with = [
            "@platforms//cpu:cpuX",
        ],
        toolchain = ":rust_cpuX_impl",
        toolchain_type = "@rules_rust//rust:exec_toolchain",
    )
    ```

    Then, either add the label of the toolchain rule to `register_toolchains` in the WORKSPACE, or pass \
    it to the `"--extra_toolchains"` flag for Bazel, and it will be used.

    See @rules_rust//rust:repositories.bzl for examples of defining the @rust_cpuX repository \
    with the actual binaries and libraries.
    """),
    implementation = _rust_exec_toolchain_impl,
    fragments = ["cpp"],
    attrs = {
        "os": attr.string(
            doc = "The operating system for the current toolchain",
            mandatory = True,
        ),
        "rustc": attr.label(
            doc = "The location of the `rustc` binary. Can be a direct source or a filegroup containing one item.",
            allow_single_file = True,
            mandatory = True,
        ),
        "rustc_lib": attr.label(
            doc = "The location of the `rustc` binary. Can be a direct source or a filegroup containing one item.",
            allow_files = True,
            mandatory = True,
        ),
        "rustc_srcs": attr.label(
            doc = "The source code of rustc.",
        ),
        "rustdoc": attr.label(
            doc = "The location of the `rustdoc` binary. Can be a direct source or a filegroup containing one item.",
            allow_single_file = True,
        ),
        "triple": attr.string(
            doc = (
                "The platform triple for the toolchains execution environment. " +
                "For more details see: https://docs.bazel.build/versions/master/skylark/rules.html#configurations"
            ),
        ),
        "_cc_toolchain": attr.label(
            default = "@bazel_tools//tools/cpp:current_cc_toolchain",
            cfg = "exec",
        ),
        "_crosstool": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
            cfg = "exec",
        ),
    },
    toolchains = [
        "@bazel_tools//tools/cpp:toolchain_type",
    ],
    incompatible_use_toolchain_transition = True,
)

rust_toolchain = rust_exec_toolchain

def _rust_target_toolchain_impl(ctx):
    compilation_mode_opts = {}
    for k, v in ctx.attr.opt_level.items():
        if not k in ctx.attr.debug_info:
            fail("Compilation mode {} is not defined in debug_info but is defined opt_level".format(k))
        compilation_mode_opts[k] = struct(debug_info = ctx.attr.debug_info[k], opt_level = v)
    for k, v in ctx.attr.debug_info.items():
        if not k in ctx.attr.opt_level:
            fail("Compilation mode {} is not defined in opt_level but is defined debug_info".format(k))

    toolchain = platform_common.ToolchainInfo(
        rust_stdlib = ctx.attr.rust_stdlib,
        binary_ext = ctx.attr.binary_ext,
        staticlib_ext = ctx.attr.staticlib_ext,
        dylib_ext = ctx.attr.dylib_ext,
        stdlib_linkflags = ctx.attr.stdlib_linkflags,
        triple = ctx.attr.triple,
        compilation_mode_opts = compilation_mode_opts,
        os = ctx.attr.os,
        default_edition = ctx.attr.default_edition,
        arch = ctx.attr.triple.split("-")[0],
        libstd_and_allocator_ccinfo = _make_libstd_and_allocator_ccinfo(ctx, ctx.attr.rust_stdlib, ctx.attr.allocator_library),
    )
    return [toolchain]

rust_target_toolchain = rule(
    doc = dedent("""\
    Declares a Rust target toolchain for use.

    This is for declaring a custom toolchain, eg. for configuring a particular version of rust or supporting a new platform.

    Example:

    Suppose the core rust team has ported the compiler to a new target CPU, called `cpuX`. This \
    support can be used in Bazel by defining a new toolchain definition and declaration:

    ```python
    load('@rules_rust//rust:toolchain.bzl', 'rust_target_toolchain')

    rust_target_toolchain(
        name = "rust_cpuX_impl",
        # see attributes...
    )

    toolchain(
        name = "rust_cpuX",
        target_compatible_with = [
            "@platforms//cpu:cpuX",
        ],
        toolchain = ":rust_cpuX_impl",
        toolchain_type = "@rules_rust//rust:target_toolchain",
    )
    ```
    """),
    implementation = _rust_target_toolchain_impl,
    fragments = ["cpp"],
    attrs = {
        "allocator_library": attr.label(
            doc = "Target that provides allocator functions when rust_library targets are embedded in a cc_binary.",
        ),
        "binary_ext": attr.string(
            doc = "The extension for binaries created from rustc.",
            mandatory = True,
        ),
        "debug_info": attr.string_dict(
            doc = "Rustc debug info levels per opt level",
            default = {
                "dbg": "2",
                "fastbuild": "0",
                "opt": "0",
            },
        ),
        "default_edition": attr.string(
            doc = "The edition to use for rust_* rules that don't specify an edition.",
            default = "2015",
        ),
        "dylib_ext": attr.string(
            doc = "The extension for dynamic libraries created from rustc.",
            mandatory = True,
        ),
        "opt_level": attr.string_dict(
            doc = "Rustc optimization levels.",
            default = {
                "dbg": "0",
                "fastbuild": "0",
                "opt": "3",
            },
        ),
        "os": attr.string(
            doc = "The operating system for the current toolchain",
            mandatory = True,
        ),
        "rust_stdlib": attr.label(
            providers = [RustStdLibInfo],
            doc = "The rust standard library.",
            mandatory = True,
        ),
        "staticlib_ext": attr.string(
            doc = "The extension for static libraries created from rustc.",
            mandatory = True,
        ),
        "stdlib_linkflags": attr.string_list(
            doc = (
                "Additional linker libs used when std lib is linked, " +
                "see https://github.com/rust-lang/rust/blob/master/src/libstd/build.rs"
            ),
            mandatory = True,
        ),
        "triple": attr.string(
            doc = (
                "The platform triple for the toolchains execution environment. " +
                "For more details see: https://docs.bazel.build/versions/master/skylark/rules.html#configurations"
            ),
        ),
        "_cc_toolchain": attr.label(
            default = "@bazel_tools//tools/cpp:current_cc_toolchain",
            cfg = "exec",
        ),
    },
    toolchains = [
        "@bazel_tools//tools/cpp:toolchain_type",
    ],
    incompatible_use_toolchain_transition = True,
)

def _rust_cargo_toolchain_impl(ctx):
    toolchain = platform_common.ToolchainInfo(
        cargo = ctx.file.cargo,
    )
    return [toolchain]

rust_cargo_toolchain = rule(
    doc = "Declares a Cargo toolchain for use.",
    implementation = _rust_cargo_toolchain_impl,
    attrs = {
        "cargo": attr.label(
            doc = "The location of the `cargo` binary.",
            allow_single_file = True,
            mandatory = True,
        ),
    },
    incompatible_use_toolchain_transition = True,
)

def _rust_clippy_toolchain_impl(ctx):
    toolchain = platform_common.ToolchainInfo(
        clippy_driver = ctx.file.clippy_driver,
    )
    return [toolchain]

rust_clippy_toolchain = rule(
    doc = "Declares a Clippy toolchain for use.",
    implementation = _rust_clippy_toolchain_impl,
    attrs = {
        "clippy_driver": attr.label(
            doc = "The location of the `clippy-driver` binary.",
            allow_single_file = True,
            mandatory = True,
        ),
    },
    incompatible_use_toolchain_transition = True,
)

def _rust_rustfmt_toolchain_impl(ctx):
    toolchain = platform_common.ToolchainInfo(
        rustfmt = ctx.file.rustfmt,
    )
    return [toolchain]

rust_rustfmt_toolchain = rule(
    doc = "Declares a Rustfmt toolchain for use.",
    implementation = _rust_rustfmt_toolchain_impl,
    attrs = {
        "rustfmt": attr.label(
            doc = "The location of the `rustfmt` binary.",
            allow_single_file = True,
            mandatory = True,
        ),
    },
    incompatible_use_toolchain_transition = True,
)

def _cargo_tool_impl(ctx):
    toolchain = ctx.toolchains[str(Label("//rust:cargo_toolchain"))]

    # Executables must be produced within the rule marked executable. To
    # satisfy this, a symlink is created.
    cargo = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = cargo,
        target_file = toolchain.cargo,
        is_executable = True,
    )

    return [DefaultInfo(
        files = depset([toolchain.cargo]),
        executable = cargo,
    )]

_cargo_tool = rule(
    doc = "A rule for fetching a `cargo` binary from a rust toolchain.",
    implementation = _cargo_tool_impl,
    toolchains = [
        str(Label("//rust:cargo_toolchain")),
    ],
    incompatible_use_toolchain_transition = True,
    executable = True,
)

def _clippy_tool_impl(ctx):
    toolchain = ctx.toolchains[str(Label("//rust:clippy_toolchain"))]

    # Executables must be produced within the rule marked executable. To
    # satisfy this, a symlink is created.
    clippy_driver = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = clippy_driver,
        target_file = toolchain.clippy_driver,
        is_executable = True,
    )

    return [DefaultInfo(
        files = depset([toolchain.clippy_driver]),
        executable = clippy_driver,
    )]

_clippy_tool = rule(
    doc = "A rule for fetching a `clippy` binary from a rust toolchain.",
    implementation = _clippy_tool_impl,
    toolchains = [
        str(Label("//rust:clippy_toolchain")),
    ],
    incompatible_use_toolchain_transition = True,
    executable = True,
)

def _rustc_tool_impl(ctx):
    toolchain = ctx.toolchains[str(Label("//rust:exec_toolchain"))]

    # Executables must be produced within the rule marked executable. To
    # satisfy this, a symlink is created.
    rustc = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = rustc,
        target_file = toolchain.rustc,
        is_executable = True,
    )

    return [DefaultInfo(
        files = depset([toolchain.rustc]),
        runfiles = ctx.runfiles(transitive_files = toolchain.rustc_lib[DefaultInfo].files),
        executable = rustc,
    )]

_rustc_tool = rule(
    doc = "A rule for fetching a `rustc` binary from a rust toolchain.",
    implementation = _rustc_tool_impl,
    toolchains = [
        str(Label("//rust:exec_toolchain")),
    ],
    incompatible_use_toolchain_transition = True,
    executable = True,
)

def _rustc_srcs_tool_impl(ctx):
    toolchain = ctx.toolchains[str(Label("//rust:exec_toolchain"))]
    srcs = []
    if toolchain.rustc_srcs:
        srcs = toolchain.rustc_srcs[DefaultInfo].files
    return [DefaultInfo(
        files = depset(srcs),
    )]

_rustc_srcs_tool = rule(
    doc = (
        "A rule for fetching a `rustc-src` artifact from a rust toolchain. " +
        "This can optionally return no files depending on whtether or not the " +
        "toolchain was setup using `include_rustc_srcs = True`."
    ),
    implementation = _rustc_srcs_tool_impl,
    toolchains = [
        str(Label("//rust:exec_toolchain")),
    ],
    incompatible_use_toolchain_transition = True,
)

def _rustfmt_tool_impl(ctx):
    toolchain = ctx.toolchains[str(Label("//rust:rustfmt_toolchain"))]

    # Executables must be produced within the rule marked executable. To
    # satisfy this, a symlink is created.
    rustfmt = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = rustfmt,
        target_file = toolchain.rustfmt,
        is_executable = True,
    )

    return [DefaultInfo(
        files = depset([toolchain.rustfmt]),
        executable = rustfmt,
    )]

_rustfmt_tool = rule(
    doc = "A rule for fetching a `rustfmt` binary from a rust toolchain.",
    implementation = _rustfmt_tool_impl,
    toolchains = [
        str(Label("//rust:rustfmt_toolchain")),
    ],
    incompatible_use_toolchain_transition = True,
    executable = True,
)

def _rustdoc_tool_impl(ctx):
    toolchain = ctx.toolchains[str(Label("//rust:exec_toolchain"))]

    # Executables must be produced within the rule marked executable. To
    # satisfy this, a symlink is created.
    rustdoc = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = rustdoc,
        target_file = toolchain.rustdoc,
        is_executable = True,
    )

    return [DefaultInfo(
        files = depset([toolchain.rustdoc]),
        executable = rustdoc,
    )]

_rustdoc_tool = rule(
    doc = "A rule for fetching a `rustdoc` binary from a rust toolchain.",
    implementation = _rustdoc_tool_impl,
    toolchains = [
        str(Label("//rust:exec_toolchain")),
    ],
    incompatible_use_toolchain_transition = True,
    executable = True,
)

toolchain_tool = struct(
    cargo = _cargo_tool,
    clippy = _clippy_tool,
    rustc_srcs = _rustc_srcs_tool,
    rustc = _rustc_tool,
    rustdoc = _rustdoc_tool,
    rustfmt = _rustfmt_tool,
)
