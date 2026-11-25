"""A standard library compiled from source, for a `rust_toolchain`'s `rust_std`.

This is part of the example rather than of rules_rust: the crate graph below
is that of one Rust release's `library/`, and it is composed of rules_rust's
public pieces alone: `rust_library`, `cargo_build_script`,
`rust_stdlib_filegroup`, a `rust_toolchain` without a `rust_std` and a
transition on `--extra_toolchains`.
"""

load("@rules_rust//cargo:defs.bzl", "cargo_build_script")
load("@rules_rust//rust:defs.bzl", "rust_common", "rust_library")
load("@rules_rust//rust:toolchain.bzl", "rust_stdlib_filegroup")

# Set, by `rust_std_from_source` alone, in the configuration its crates are
# built in; `BUILD.bazel` declares it. The `toolchain` the macro declares for
# the `rust_toolchain` without a standard library is conditioned on it, so
# that toolchain is never picked anywhere else, the execution configuration
# of those very crates included.
_BUILDING_STD = Label("//:building_std")
_BUILDING_STD_ON = Label("//:building_std_on")

def _crate_root_impl(ctx):
    """The one file among `srcs` at `path`, or at `file` in the vendored crate `vendored`.

    rust-src vendors its dependencies as `vendor/<name>-<version>/`, and the
    version is not something a BUILD file should have to know.
    """
    matches = []
    for file in ctx.files.srcs:
        path = file.short_path
        if ctx.attr.path:
            if path == ctx.attr.path or path.endswith("/" + ctx.attr.path):
                matches.append(file)
        else:
            marker = "vendor/" + ctx.attr.vendored + "-"
            index = path.find(marker)
            if index == -1 or (index > 0 and path[index - 1] != "/"):
                continue
            rest = path[index + len(marker):]
            version, _, within = rest.partition("/")
            if version[:1].isdigit() and within == ctx.attr.file:
                matches.append(file)
    what = ctx.attr.path or "{} of the vendored crate {}".format(ctx.attr.file, ctx.attr.vendored)
    if len(matches) != 1:
        fail("{}: expected one file at {} among the sources, found {}".format(
            ctx.label,
            what,
            [file.short_path for file in matches] or "none",
        ))
    return [DefaultInfo(files = depset(matches))]

_crate_root = rule(
    implementation = _crate_root_impl,
    doc = "Picks a crate root out of rust-src's files by path, so a BUILD file names no vendored crate's version.",
    attrs = {
        "file": attr.string(
            doc = "The file within the vendored crate.",
            default = "src/lib.rs",
        ),
        "path": attr.string(
            doc = "The path of the file, relative to the tree `srcs` are from. Exclusive with `vendored`.",
        ),
        "srcs": attr.label_list(
            doc = "The files to pick from.",
            allow_files = True,
            mandatory = True,
        ),
        "vendored": attr.string(
            doc = "The name of a crate under `vendor/`, whose `file` is picked.",
        ),
    },
)

def _building_std_transition_impl(settings, attr):
    return {
        "//command_line_option:extra_toolchains": [str(attr.toolchain)] + settings["//command_line_option:extra_toolchains"],
        str(_BUILDING_STD): True,
    }

# The standard library is built by a toolchain without one, which must win
# resolution for the crates and nothing else. `--extra_toolchains` puts the
# `toolchain` declared for it ahead of every registered toolchain for this
# subgraph, so it is never registered, and that `toolchain` is conditioned on
# `building_std`, which this transition alone sets, so the build scripts and
# other tools compiled for the execution platform along the way get the
# registered toolchain even when the target is the host.
_building_std_transition = transition(
    implementation = _building_std_transition_impl,
    inputs = ["//command_line_option:extra_toolchains"],
    outputs = ["//command_line_option:extra_toolchains", str(_BUILDING_STD)],
)

def _std_from_source_files_impl(ctx):
    return [DefaultInfo(files = depset(transitive = [dep[DefaultInfo].files for dep in ctx.attr.deps]))]

_std_from_source_files = rule(
    implementation = _std_from_source_files_impl,
    doc = "The outputs of the standard library's crates, built with the toolchain `toolchain` names.",
    cfg = _building_std_transition,
    attrs = {
        "deps": attr.label_list(
            doc = "The crates of the standard library.",
            providers = [rust_common.crate_info],
        ),
        "toolchain": attr.label(
            doc = "The `toolchain` declared for the `rust_toolchain` without a `rust_std`.",
            mandatory = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = Label("@bazel_tools//tools/allowlists/function_transition_allowlist"),
        ),
    },
)

def _crate(name, root = None, vendored = None, edition = "2024", deps = [], aliases = {}, features = [], build_script = False):
    """A crate of the standard library and how rust-lang's bootstrap builds it.

    Args:
        name (str): The crate's name.
        root (str): The crate root, relative to rust-src's root, for an in-tree crate.
        vendored (str): The name of a vendored crate, whose root is `src/lib.rs`.
        edition (str): The crate's edition, from its `Cargo.toml`.
        deps (list[str]): The crates it depends on, by name.
        aliases (dict[str, str]): The crates it depends on under another name, as
            Cargo's `package =` renames them: `rustc_std_workspace_core` is `core` to most.
        features (list[str]): The Cargo features it is built with.
        build_script (bool): Whether it has a `build.rs` to run, which sets cfgs from the target.

    Returns:
        struct: The crate.
    """
    return struct(
        name = name,
        root = root,
        vendored = vendored,
        edition = edition,
        deps = deps,
        aliases = aliases,
        features = features,
        build_script = build_script,
    )

_CORE = _crate("core", root = "library/core/src/lib.rs")
_COMPILER_BUILTINS = _crate(
    "compiler_builtins",
    root = "library/compiler-builtins/compiler-builtins/src/lib.rs",
    deps = ["core"],
    features = ["arch", "compiler-builtins", "unmangled-names"],
)
_ALLOC = _crate("alloc", root = "library/alloc/src/lib.rs", deps = ["core", "compiler_builtins"])

# What a `no_std` program needs, in dependency order.
_NO_STD_CRATES = [_CORE, _COMPILER_BUILTINS, _ALLOC]

# What a program with `std` needs on a Unix-like target with a C library, in
# dependency order: the graph of `library/Cargo.lock` with the `panic-unwind`
# feature and without `backtrace`, which would add `addr2line` and its
# dependencies. The `rustc_std_workspace_*` shims re-export `core`, `alloc`
# and `std` for the vendored crates, which name them through Cargo renames.
_STD_CRATES = [
    _CORE,
    _COMPILER_BUILTINS,
    _crate("rustc_std_workspace_core", root = "library/rustc-std-workspace-core/lib.rs", deps = ["core", "compiler_builtins"]),
    _ALLOC,
    _crate("rustc_std_workspace_alloc", root = "library/rustc-std-workspace-alloc/lib.rs", deps = ["alloc"]),
    _crate("cfg_if", vendored = "cfg-if", edition = "2018", aliases = {"rustc_std_workspace_core": "core"}, features = ["rustc-dep-of-std", "core"]),
    _crate("libc", vendored = "libc", edition = "2021", deps = ["rustc_std_workspace_core"], features = ["rustc-dep-of-std", "align", "rustc-std-workspace-core"], build_script = True),
    _crate("unwind", root = "library/unwind/src/lib.rs", deps = ["libc"], aliases = {"rustc_std_workspace_core": "core"}),
    _crate("panic_abort", root = "library/panic_abort/src/lib.rs", aliases = {"rustc_std_workspace_core": "core"}),
    _crate("panic_unwind", root = "library/panic_unwind/src/lib.rs", deps = ["alloc", "unwind", "libc"], aliases = {"rustc_std_workspace_core": "core"}),
    _crate(
        "hashbrown",
        vendored = "hashbrown",
        aliases = {"rustc_std_workspace_alloc": "alloc", "rustc_std_workspace_core": "core"},
        features = ["rustc-dep-of-std", "nightly", "core", "alloc", "rustc-internal-api"],
    ),
    _crate("rustc_demangle", vendored = "rustc-demangle", edition = "2015", aliases = {"rustc_std_workspace_core": "core"}, features = ["rustc-dep-of-std", "core"]),
    _crate("std_detect", root = "library/std_detect/src/lib.rs", deps = ["libc"], aliases = {"rustc_std_workspace_alloc": "alloc", "rustc_std_workspace_core": "core"}),
    _crate(
        "std",
        root = "library/std/src/lib.rs",
        deps = ["alloc", "cfg_if", "panic_unwind", "panic_abort", "core", "unwind", "hashbrown", "std_detect", "rustc_demangle", "libc"],
        features = ["panic-unwind"],
        build_script = True,
    ),
    _crate("rustc_std_workspace_std", root = "library/rustc-std-workspace-std/lib.rs", deps = ["std"]),
    _crate("getopts", vendored = "getopts", edition = "2021", aliases = {"rustc_std_workspace_core": "core", "rustc_std_workspace_std": "std"}, features = ["rustc-dep-of-std", "core", "std"]),
    _crate("test", root = "library/test/src/lib.rs", deps = ["getopts", "std", "core", "libc"]),
    _crate("rustc_literal_escaper", vendored = "rustc-literal-escaper", edition = "2021", aliases = {"rustc_std_workspace_core": "core"}, features = ["rustc-dep-of-std", "core"]),
    _crate("proc_macro", root = "library/proc_macro/src/lib.rs", deps = ["std", "core", "rustc_literal_escaper"], features = ["rustc-dep-of-std"]),
]

# The cfgs `compiler_builtins`'s build script sets from the target, as flags.
# `f16_enabled` and `f128_enabled` go where rustc reports the types reliable
# (`--print cfg` lists `target_has_reliable_f16` and `_f128`), which these
# architectures are; `mem_unaligned` where unaligned access is supported.
_COMPILER_BUILTINS_FLAGS = select({
    "@platforms//cpu:aarch64": ["--cfg=f128_enabled", "--cfg=f16_enabled", "--cfg=intrinsics_enabled", "--cfg=mem_unaligned"],
    "@platforms//cpu:x86_64": ["--cfg=f128_enabled", "--cfg=f16_enabled", "--cfg=intrinsics_enabled", "--cfg=mem_unaligned"],
    "//conditions:default": ["--cfg=intrinsics_enabled"],
})

def rust_std_from_source(
        name,
        srcs,
        rust_toolchain,
        target_compatible_with,
        exec_compatible_with = [],
        std = False,
        compile_data = [],
        rustc_flags = [],
        compiler_builtins_features = None,
        compiler_builtins_flags = _COMPILER_BUILTINS_FLAGS,
        visibility = None,
        tags = [],
        **kwargs):
    """Compiles the standard library from rust-src for a `rust_toolchain`'s `rust_std`.

    The standard library a toolchain carries is normally unpacked from a
    `rust-std` distribution, compiled by rust-lang for that target with their
    flags. A target they do not ship it for, or flags of one's own (a panic
    strategy, frame pointers, a float ABI) call for compiling it here, the way
    `cargo -Zbuild-std` does.

    Without `std` the result is `core`, `compiler_builtins` and `alloc`, what a
    `no_std` program needs. With it, it is the standard library of a Unix-like
    target with a C library: the crates above, `std`, `test` for the test
    harness, `proc_macro`, and the vendored crates they depend on, `libc`
    among them, with the `panic-unwind` feature and without `backtrace`. The
    rlibs only: `std` is not built as a dylib, so `link_std_dylib` is not
    available with it and proc macros, which need one, are left to the
    toolchain of the execution platform.

    The crates are ordinary `rust_library` targets, named `<name>.core` and so
    on, with `RUSTC_BOOTSTRAP` set and `-Zforce-unstable-if-unmarked` passed as
    bootstrap passes them. `libc` and `std` run their build scripts. They are
    built by `rust_toolchain`, which must have no `rust_std` and is otherwise
    the toolchain the result is for, since the toolchain that carries a
    standard library cannot be the one that builds it. The macro declares a
    `toolchain` for it, puts that ahead of every registered toolchain for the
    crates alone, and conditions it on a setting only that transition sets, so
    nothing else, the crates' own build scripts included, ever resolves it.
    `<name>` is the `rust_stdlib_filegroup` of the outputs, which a
    `rust_toolchain` takes as `rust_std`. From `BUILD.bazel`:

    ```python
    rust_toolchain(
        name = "std_bootstrap_rust_toolchain",
        rustc = "@rules_rust//rust/toolchain:current_rustc_files",
        # ... and no `rust_std`.
    )

    rust_std_from_source(
        name = "std_library",
        srcs = "@rust_src//:library_rs",
        compile_data = ["@rust_src//:library"],
        rust_toolchain = ":std_bootstrap_rust_toolchain",
        target_compatible_with = [":std_from_source"],
        std = True,
    )

    rust_toolchain(
        name = "std_rust_toolchain",
        rust_std = ":std_library",
        # ... the same as the bootstrap toolchain otherwise.
    )
    ```

    `compiler_builtins`' build script does not run. Its Cargo features and
    the cfgs it sets from the target are `compiler_builtins_features` and
    `compiler_builtins_flags`, with defaults for an architecture rustc reports
    `f16` and `f128` reliable for, and `mem` on for a `no_std` target, which
    has no C library to provide `memcpy`.

    Args:
        name (str): The name of the `rust_stdlib_filegroup`.
        srcs (Label): The `.rs` files of rust-src, `library/` and the crates
            under `library/vendor/` the standard library needs, as one target.
            The crate roots are picked out of them by path.
        rust_toolchain (Label): A `rust_toolchain` without a `rust_std` and with
            the attributes of the toolchain the result is for.
        target_compatible_with (list): The constraints of the platform `rust_toolchain` compiles for.
        exec_compatible_with (list): The constraints of the platform `rust_toolchain` runs on.
        std (bool): Whether to build `std` and the rest of a hosted target's
            standard library, or only what `no_std` needs.
        compile_data (list): The other files of the tree, which the crates `include!`.
        rustc_flags (list): Flags for every crate, after the ones above.
        compiler_builtins_features (list): The Cargo features of `compiler_builtins`
            besides `arch`, `compiler-builtins` and `unmangled-names`. `["mem"]`
            without `std`, `[]` with it, when unset.
        compiler_builtins_flags (list): Flags for `compiler_builtins` alone: the
            `--cfg`s its build script would set from the target.
        visibility (list): The visibility of the `rust_stdlib_filegroup`.
        tags (list): Tags for every target.
        **kwargs (dict): Other arguments for every `rust_library`.
    """
    if compiler_builtins_features == None:
        compiler_builtins_features = [] if std else ["mem"]

    private = dict(
        tags = ["manual"] + tags,
        visibility = ["//visibility:private"],
    )
    common = dict(
        srcs = [srcs],
        compile_data = compile_data,
        rustc_env = {"RUSTC_BOOTSTRAP": "1"},
        **(private | kwargs)
    )
    common_flags = ["-Zforce-unstable-if-unmarked", "--cap-lints=allow"]

    targets = {}
    for crate in _STD_CRATES if std else _NO_STD_CRATES:
        target = "{}.{}".format(name, crate.name)
        targets[crate.name] = target

        _crate_root(
            name = target + ".root",
            srcs = [srcs],
            path = crate.root or "",
            vendored = crate.vendored or "",
            **private
        )

        flags = common_flags + rustc_flags
        features = list(crate.features)
        if crate.name == "compiler_builtins":
            flags = common_flags + compiler_builtins_flags + rustc_flags
            features = features + compiler_builtins_features

        deps = [":" + targets[dep] for dep in crate.deps + crate.aliases.keys()]
        if crate.build_script:
            _crate_root(
                name = target + ".build_script.root",
                srcs = [srcs],
                path = crate.root.rsplit("/src/", 1)[0] + "/build.rs" if crate.root else "",
                vendored = crate.vendored or "",
                file = "build.rs",
                **private
            )
            cargo_build_script(
                name = target + ".build_script",
                srcs = [srcs],
                crate_name = "build_script_build",
                crate_root = ":" + target + ".build_script.root",
                crate_features = features,
                edition = crate.edition,
                **private
            )
            deps.append(":" + target + ".build_script")

        rust_library(
            name = target,
            crate_name = crate.name,
            crate_root = ":" + target + ".root",
            crate_features = features,
            edition = crate.edition,
            rustc_flags = flags,
            deps = deps,
            aliases = {":" + targets[dep]: alias for dep, alias in crate.aliases.items()},
            **common
        )

    native.toolchain(
        name = name + ".toolchain",
        toolchain = rust_toolchain,
        toolchain_type = "@rules_rust//rust:toolchain_type",
        exec_compatible_with = exec_compatible_with,
        target_compatible_with = target_compatible_with,
        target_settings = [str(_BUILDING_STD_ON)],
        **private
    )

    _std_from_source_files(
        name = name + ".files",
        deps = [":" + target for target in targets.values()],
        toolchain = ":" + name + ".toolchain",
        **private
    )

    rust_stdlib_filegroup(
        name = name,
        srcs = [":" + name + ".files"],
        tags = tags,
        visibility = visibility,
    )
