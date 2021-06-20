"""
[summary]
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load(
    "//rust/platform:triple_mappings.bzl",
    "SUPPORTED_PLATFORM_TRIPLES",
    "system_to_binary_ext",
    "system_to_dylib_ext",
    "system_to_staticlib_ext",
    "system_to_stdlib_linkflags",
    "triple_to_constraint_set",
    "triple_to_system",
)
load(
    "//rust/private:repository_utils.bzl",
    "DEFAULT_STATIC_RUST_URL_TEMPLATES",
    "check_version_valid",
    "load_cargo",
    "load_clippy",
    "load_llvm_tools",
    "load_rust_compiler",
    "load_rust_src",
    "load_rust_stdlib",
    "load_rustc_dev_nightly",
    "load_rustfmt",
    _load_arbitrary_tool = "load_arbitrary_tool",
)

# Reexport to satisfy previsouly public API
load_arbitrary_tool = _load_arbitrary_tool

# Note: Code in `.github/workflows/crate_universe.yaml` looks for this line, if you remove it or change its format, you will also need to update that code.
DEFAULT_RUST_VERSION = "1.53.0"
DEFAULT_RUST_EDITION = "2015"
AVAILABLE_RUST_EDITIONS = ["2015", "2018", "2021"]
DEFAULT_TOOLCHAIN_TRIPLES = [
    "aarch64-apple-darwin",
    "aarch64-unknown-linux-gnu",
    "x86_64-apple-darwin",
    "x86_64-pc-windows-msvc",
    "x86_64-unknown-freebsd",
    "x86_64-unknown-linux-gnu",
]

_WORKSPACE = """\
workspace(name = "{}")
"""

_EXEC_TOOLCHAIN_BUILD_FILE = """\
load(
    "@rules_rust//rust:toolchain.bzl", 
    "rust_cargo_toolchain",
    "rust_clippy_toolchain",
    "rust_exec_toolchain",
    "rust_rustfmt_toolchain",
)

package(default_visibility = ["//visibility:public"])

rust_exec_toolchain(
    name = "exec_toolchain",
    os = "{os}",
    rustc = "{rustc}",
    rustc_lib = "{rustc_lib}",
    rustc_srcs = {rustc_srcs},
    triple = "{triple}",
    rustdoc = "{rustdoc}",
)

toolchain(
    name = "toolchain",
    exec_compatible_with = {constraints},
    toolchain = ":exec_toolchain",
    toolchain_type = "@rules_rust//rust:exec_toolchain",
)

alias(
    name = "{name}",
    actual = ":toolchain",
)

rust_cargo_toolchain(
    name = "exec_cargo_toolchain",
    cargo = "{cargo}",
)

toolchain(
    name = "cargo_toolchain",
    exec_compatible_with = {constraints},
    toolchain = ":exec_cargo_toolchain",
    toolchain_type = "@rules_rust//rust:cargo_toolchain",
)

rust_clippy_toolchain(
    name = "exec_clippy_toolchain",
    clippy_driver = "{clippy}",
)

toolchain(
    name = "clippy_toolchain",
    exec_compatible_with = {constraints},
    toolchain = ":exec_clippy_toolchain",
    toolchain_type = "@rules_rust//rust:clippy_toolchain",
)

rust_rustfmt_toolchain(
    name = "exec_rustfmt_toolchain",
    rustfmt = "{rustfmt}",
)

toolchain(
    name = "rustfmt_toolchain",
    exec_compatible_with = {constraints},
    toolchain = ":exec_rustfmt_toolchain",
    toolchain_type = "@rules_rust//rust:rustfmt_toolchain",
)
"""

def _rust_exec_toolchain_repository_impl(repository_ctx):
    tools_repository = repository_ctx.attr.tools_repository
    triple = repository_ctx.attr.triple
    system = triple_to_system(triple)

    include_rustc_srcs_env = repository_ctx.os.environ.get("RULES_RUST_TOOLCHAIN_INCLUDE_RUSTC_SRCS")
    if include_rustc_srcs_env != None:
        include_rustc_srcs = include_rustc_srcs_env.lower() in ["true", "1"]
    else:
        include_rustc_srcs = repository_ctx.attr.include_rustc_srcs
    rustc_srcs = "\"{}\"".format(repository_ctx.attr.rustc_srcs) if include_rustc_srcs else None

    build_file_contents = _EXEC_TOOLCHAIN_BUILD_FILE.format(
        name = repository_ctx.name,
        os = system,
        rustc = "@{}//:rustc".format(tools_repository),
        rustc_lib = "@{}//:rustc_lib".format(tools_repository),
        rustc_srcs = rustc_srcs,
        triple = triple,
        constraints = triple_to_constraint_set(triple),
        rustdoc = "@{}//:rustdoc".format(tools_repository),
        rustfmt = repository_ctx.attr.rustfmt,
        cargo = repository_ctx.attr.cargo,
        clippy = repository_ctx.attr.clippy,
    )

    repository_ctx.file("BUILD.bazel", build_file_contents)
    repository_ctx.file("WORKSPACE.bazel", _WORKSPACE.format(repository_ctx.name))

_rust_exec_toolchain_repository = repository_rule(
    doc = "must be a host toolchain",
    attrs = {
        "cargo": attr.string(
            doc = "",
        ),
        "clippy": attr.string(
            doc = "",
        ),
        "edition": attr.string(
            doc = "",
            values = AVAILABLE_RUST_EDITIONS,
            default = DEFAULT_RUST_EDITION,
        ),
        "include_rustc_srcs": attr.bool(
            default = False,
        ),
        "rustc_srcs": attr.string(
            doc = "",
        ),
        "rustfmt": attr.string(
            doc = "",
        ),
        "tools_repository": attr.string(
            doc = "",
            mandatory = True,
        ),
        "triple": attr.string(
            doc = "The Rust-style target that this compiler runs on",
            mandatory = True,
        ),
    },
    implementation = _rust_exec_toolchain_repository_impl,
    environ = ["RULES_RUST_TOOLCHAIN_INCLUDE_RUSTC_SRCS"],
)

_TARGET_TOOLCHAIN_BUILD_FILE = """\
load("@rules_rust//rust:toolchain.bzl", "rust_target_toolchain")

package(default_visibility = ["//visibility:public"])

rust_target_toolchain(
    name = "target_toolchain",
    allocator_library = {allocator_library},
    binary_ext = "{binary_ext}",
    default_edition = "{default_edition}",
    os = "{os}",
    dylib_ext = "{dylib_ext}",
    rust_stdlib = "{rust_stdlib}",
    staticlib_ext = "{staticlib_ext}",
    stdlib_linkflags = {stdlib_linkflags},
    triple = "{triple}",
)

toolchain(
    name = "toolchain",
    target_compatible_with = {constraints},
    toolchain = ":target_toolchain",
    toolchain_type = "@rules_rust//rust:target_toolchain",
)

alias(
    name = "{name}",
    actual = ":toolchain",
)
"""

def _rust_target_toolchain_repository_impl(repository_ctx):
    tools_repository = repository_ctx.attr.tools_repository
    triple = repository_ctx.attr.triple
    system = triple_to_system(triple)

    stdlib_linkflags = repository_ctx.attr.stdlib_linkflags
    allocator_library = "\"{}\"".format(repository_ctx.attr.allocator_library) if repository_ctx.attr.allocator_library else None

    stdlib_linkflags = None
    if "BAZEL_RUST_STDLIB_LINKFLAGS" in repository_ctx.os.environ:
        stdlib_linkflags = repository_ctx.os.environ["BAZEL_RUST_STDLIB_LINKFLAGS"].split(":")
    if stdlib_linkflags == None:
        stdlib_linkflags = ["\"{}\"".format(f) for f in system_to_stdlib_linkflags(system)]

    build_file_contents = _TARGET_TOOLCHAIN_BUILD_FILE.format(
        name = repository_ctx.name,
        allocator_library = allocator_library,
        binary_ext = system_to_binary_ext(system),
        default_edition = repository_ctx.attr.edition,
        dylib_ext = system_to_dylib_ext(system),
        os = system,
        rust_stdlib = "@{}//:rust_lib-{}".format(tools_repository, triple),
        staticlib_ext = system_to_staticlib_ext(system),
        stdlib_linkflags = stdlib_linkflags,
        triple = triple,
        constraints = triple_to_constraint_set(triple),
    )

    repository_ctx.file("BUILD.bazel", build_file_contents)
    repository_ctx.file("WORKSPACE.bazel", _WORKSPACE.format(repository_ctx.name))

_rust_target_toolchain_repository = repository_rule(
    doc = "must be a host toolchain",
    attrs = {
        "allocator_library": attr.label(
            doc = "Target that provides allocator functions when rust_library targets are embedded in a cc_binary.",
        ),
        "edition": attr.string(
            doc = "",
            values = AVAILABLE_RUST_EDITIONS,
            default = DEFAULT_RUST_EDITION,
        ),
        "stdlib_linkflags": attr.string_list(
            doc = "",
        ),
        "tools_repository": attr.string(
            doc = "",
            mandatory = True,
        ),
        "triple": attr.string(
            doc = "The Rust-style target that this compiler runs on",
            mandatory = True,
        ),
    },
    implementation = _rust_target_toolchain_repository_impl,
    environ = ["BAZEL_RUST_STDLIB_LINKFLAGS"],
)

def _rust_rustc_repository_impl(ctx):
    """The implementation of the rust toolchain repository rule."""

    check_version_valid(ctx.attr.version, ctx.attr.iso_date)

    build_components = [load_rust_compiler(ctx)]

    # Rust 1.45.0 and nightly builds after 2020-05-22 need the llvm-tools gzip to get the libLLVM dylib
    if ctx.attr.version >= "1.45.0" or (ctx.attr.version == "nightly" and ctx.attr.iso_date > "2020-05-22"):
        load_llvm_tools(ctx, ctx.attr.triple)

    if ctx.attr.dev_components:
        load_rustc_dev_nightly(ctx, ctx.attr.triple)

    ctx.file("WORKSPACE.bazel", _WORKSPACE.format(ctx.name))
    ctx.file("BUILD.bazel", "\n".join(build_components))

rust_rustc_repository = repository_rule(
    doc = "must be a host toolchain",
    attrs = {
        "dev_components": attr.bool(
            doc = "Whether to download the rustc-dev components (defaults to False). Requires version to be \"nightly\".",
            default = False,
        ),
        "iso_date": attr.string(
            doc = "The date of the tool (or None, if the version is a specific version).",
        ),
        "sha256s": attr.string_dict(
            doc = "A dict associating tool subdirectories to sha256 hashes. See [rust_repositories](#rust_repositories) for more details.",
        ),
        "triple": attr.string(
            doc = "The Rust-style target that this compiler runs on",
            mandatory = True,
        ),
        "urls": attr.string_list(
            doc = "A list of mirror urls containing the tools from the Rust-lang static file server. These must contain the '{}' used to substitute the tool being fetched (using .format).",
            default = DEFAULT_STATIC_RUST_URL_TEMPLATES,
        ),
        "version": attr.string(
            doc = "The version of the tool among \"nightly\", \"beta\", or an exact version.",
            mandatory = True,
        ),
    },
    implementation = _rust_rustc_repository_impl,
)

# buildifier: disable=unnamed-macro
def rust_exec_toolchain_repository(
        prefix,
        triple,
        version = DEFAULT_RUST_VERSION,
        edition = DEFAULT_RUST_EDITION,
        urls = DEFAULT_STATIC_RUST_URL_TEMPLATES,
        iso_date = None,
        sha256s = None,
        dev_components = False,
        include_rustc_srcs = False,
        rustfmt_version = None,
        rustfmt_iso_date = None):
    """[summary]

    Args:
        prefix ([type]): [description]
        triple ([type]): [description]
        version ([type], optional): [description]. Defaults to DEFAULT_RUST_VERSION.
        edition ([type], optional): [description]. Defaults to DEFAULT_RUST_EDITION.
        urls ([type], optional): [description]. Defaults to DEFAULT_STATIC_RUST_URL_TEMPLATES.
        iso_date ([type], optional): [description]. Defaults to None.
        sha256s ([type], optional): [description]. Defaults to None.
        dev_components (bool, optional): [description]. Defaults to False.
        include_rustc_srcs (bool, optional): [description]. Defaults to False.
        rustfmt_version ([type], optional): [description]. Defaults to None.
        rustfmt_iso_date ([type], optional): [description]. Defaults to None.
    """
    version_str = version if version not in ["nightly", "beta"] else "{}-{}".format(
        version,
        iso_date,
    )
    repo_id = "{}_{}".format(version_str, triple)

    tools_repo_name = "{}_compiler_{}".format(prefix, repo_id)
    rust_rustc_repository(
        name = tools_repo_name,
        dev_components = dev_components,
        triple = triple,
        iso_date = iso_date,
        sha256s = sha256s,
        urls = urls,
        version = version,
    )

    # rustc_srcs are platform agnostic so it should be something
    # defined once and shared accross various toolchains
    rustc_srcs_name = "{}_rustc_srcs_{}".format(prefix, version_str)
    maybe(
        rust_srcs_repository,
        name = rustc_srcs_name,
        iso_date = iso_date,
        urls = urls,
        sha256 = sha256s.get("rustc-src") if sha256s else None,
        version = version,
    )

    rustfmt_version_str = version_str
    if rustfmt_version:
        rustfmt_version_str = rustfmt_version if rustfmt_version not in ["nightly", "beta"] else "{}-{}".format(
            rustfmt_version,
            rustfmt_iso_date,
        )
    rustfmt_repo_id = "{}_{}".format(rustfmt_version_str, triple)

    rustfmt_name = "{}_rustfmt_{}".format(prefix, rustfmt_repo_id)
    rust_rustfmt_repository(
        name = rustfmt_name,
        version = rustfmt_version or version,
        iso_date = rustfmt_iso_date or iso_date,
        triple = triple,
    )

    cargo_name = "{}_cargo_{}".format(prefix, repo_id)
    rust_cargo_repository(
        name = cargo_name,
        version = version,
        iso_date = iso_date,
        triple = triple,
    )

    clippy_name = "{}_clippy_{}".format(prefix, repo_id)
    rust_clippy_repository(
        name = clippy_name,
        version = version,
        iso_date = iso_date,
        triple = triple,
    )

    toolchain_name = "{}_{}".format(prefix, repo_id)
    _rust_exec_toolchain_repository(
        name = toolchain_name,
        tools_repository = tools_repo_name,
        edition = edition,
        triple = triple,
        include_rustc_srcs = include_rustc_srcs,
        clippy = "@{}//:clippy_driver_bin".format(clippy_name),
        cargo = "@{}//:cargo".format(cargo_name),
        rustfmt = "@{}//:rustfmt_bin".format(rustfmt_name),
        rustc_srcs = "@{}//:rustc_srcs".format(rustc_srcs_name),
    )
    native.register_toolchains(*[
        tool.format(toolchain_name)
        for tool in [
            "@{}//:toolchain",
            "@{}//:cargo_toolchain",
            "@{}//:clippy_toolchain",
            "@{}//:rustfmt_toolchain",
        ]
    ])

def _rust_target_stdlib_repository_impl(ctx):
    """The implementation of the rust-std target toolchain repository rule."""

    check_version_valid(ctx.attr.version, ctx.attr.iso_date)

    ctx.file("BUILD.bazel", load_rust_stdlib(ctx, ctx.attr.triple))
    ctx.file("WORKSPACE.bazel", _WORKSPACE.format(ctx.name))

rust_target_stdlib_repository = repository_rule(
    doc = "",
    attrs = {
        "edition": attr.string(
            doc = "The rust edition to be used by default.",
            default = "2015",
        ),
        "iso_date": attr.string(
            doc = "The date of the tool (or None, if the version is a specific version).",
        ),
        "sha256s": attr.string_dict(
            doc = "A dict associating tool subdirectories to sha256 hashes. See [rust_repositories](#rust_repositories) for more details.",
        ),
        "triple": attr.string(
            doc = "The Rust-style target that this compiler runs on",
            mandatory = True,
        ),
        "urls": attr.string_list(
            doc = "A list of mirror urls containing the tools from the Rust-lang static file server. These must contain the '{}' used to substitute the tool being fetched (using .format).",
            default = DEFAULT_STATIC_RUST_URL_TEMPLATES,
        ),
        "version": attr.string(
            doc = "The version of the tool among \"nightly\", \"beta\", or an exact version.",
            mandatory = True,
        ),
    },
    implementation = _rust_target_stdlib_repository_impl,
)

# buildifier: disable=unnamed-macro
def rust_target_toolchain_repository(
        prefix,
        triple,
        edition = DEFAULT_RUST_EDITION,
        version = DEFAULT_RUST_VERSION,
        urls = DEFAULT_STATIC_RUST_URL_TEMPLATES,
        allocator_library = None,
        iso_date = None,
        sha256s = None):
    """[summary]

    Args:
        prefix ([type]): [description]
        triple ([type]): [description]
        version ([type], optional): [description]. Defaults to DEFAULT_RUST_VERSION.
        urls ([type], optional): [description]. Defaults to DEFAULT_STATIC_RUST_URL_TEMPLATES.
        allocator_library ([type], optional): [description]. Defaults to None.
        iso_date ([type], optional): [description]. Defaults to None.
        sha256s ([type], optional): [description]. Defaults to None.
    """
    version_str = version if version not in ["nightly", "beta"] else "{}-{}".format(
        version,
        iso_date,
    )
    repo_id = "{}_{}".format(version_str, triple)

    stdlib_repo_name = "{}_stdlib_{}".format(prefix, repo_id)
    rust_target_stdlib_repository(
        name = stdlib_repo_name,
        triple = triple,
        iso_date = iso_date,
        sha256s = sha256s,
        urls = urls,
        version = version,
    )

    toolchain_name = "{}_toolchain_{}".format(prefix, repo_id)
    _rust_target_toolchain_repository(
        name = toolchain_name,
        tools_repository = stdlib_repo_name,
        triple = triple,
        allocator_library = allocator_library,
        edition = edition,
    )

    native.register_toolchains("@{}//:toolchain".format(toolchain_name))

def _rust_srcs_repository_impl(repository_ctx):
    """[summary]

    Args:
        repository_ctx ([type]): [description]
    """
    repository_ctx.file("BUILD.bazel", load_rust_src(repository_ctx))
    repository_ctx.file("WORKSPACE.bazel", _WORKSPACE.format(repository_ctx.name))

rust_srcs_repository = repository_rule(
    doc = "",
    implementation = _rust_srcs_repository_impl,
    attrs = {
        "iso_date": attr.string(
            doc = "The date of the tool (or None, if the version is a specific version).",
        ),
        "sha256": attr.string(
            doc = "The sha256 of the rustc-src artifact.",
        ),
        "urls": attr.string_list(
            doc = "A list of mirror urls containing the tools from the Rust-lang static file server. These must contain the '{}' used to substitute the tool being fetched (using .format).",
            default = DEFAULT_STATIC_RUST_URL_TEMPLATES,
        ),
        "version": attr.string(
            doc = "The version of the tool among \"nightly\", \"beta\", or an exact version.",
            mandatory = True,
        ),
    },
)

def _rust_rustfmt_repository_impl(repository_ctx):
    """[summary]

    Args:
        repository_ctx ([type]): [description]
    """
    repository_ctx.file("BUILD.bazel", load_rustfmt(repository_ctx))
    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")""".format(repository_ctx.name))

rust_rustfmt_repository = repository_rule(
    doc = "",
    implementation = _rust_rustfmt_repository_impl,
    attrs = {
        "iso_date": attr.string(
            doc = "The date of the tool (or None, if the version is a specific version).",
        ),
        "sha256": attr.string(
            doc = "The sha256 of the rustfmt artifact.",
        ),
        "triple": attr.string(
            doc = "The Rust-style target that this compiler runs on",
            mandatory = True,
        ),
        "urls": attr.string_list(
            doc = "A list of mirror urls containing the tools from the Rust-lang static file server. These must contain the '{}' used to substitute the tool being fetched (using .format).",
            default = DEFAULT_STATIC_RUST_URL_TEMPLATES,
        ),
        "version": attr.string(
            doc = "The version of the tool among \"nightly\", \"beta\", or an exact version.",
            mandatory = True,
        ),
    },
)

def _rust_cargo_repository_impl(repository_ctx):
    """[summary]

    Args:
        repository_ctx ([type]): [description]
    """
    repository_ctx.file("BUILD.bazel", load_cargo(repository_ctx))
    repository_ctx.file("WORKSPACE.bazel", _WORKSPACE.format(repository_ctx.name))

rust_cargo_repository = repository_rule(
    doc = "",
    implementation = _rust_cargo_repository_impl,
    attrs = {
        "iso_date": attr.string(
            doc = "The date of the tool (or None, if the version is a specific version).",
        ),
        "sha256": attr.string(
            doc = "The sha256 of the cargo artifact.",
        ),
        "triple": attr.string(
            doc = "The Rust-style target that this compiler runs on",
            mandatory = True,
        ),
        "urls": attr.string_list(
            doc = "A list of mirror urls containing the tools from the Rust-lang static file server. These must contain the '{}' used to substitute the tool being fetched (using .format).",
            default = DEFAULT_STATIC_RUST_URL_TEMPLATES,
        ),
        "version": attr.string(
            doc = "The version of the tool among \"nightly\", \"beta\", or an exact version.",
            mandatory = True,
        ),
    },
)

def _rust_clippy_repository_impl(repository_ctx):
    """[summary]

    Args:
        repository_ctx ([type]): [description]
    """
    repository_ctx.file("BUILD.bazel", load_clippy(repository_ctx))
    repository_ctx.file("WORKSPACE.bazel", _WORKSPACE.format(repository_ctx.name))

rust_clippy_repository = repository_rule(
    doc = "",
    implementation = _rust_clippy_repository_impl,
    attrs = {
        "iso_date": attr.string(
            doc = "The date of the tool (or None, if the version is a specific version).",
        ),
        "sha256": attr.string(
            doc = "The sha256 of the clippy-driver artifact.",
        ),
        "triple": attr.string(
            doc = "The Rust-style target that this compiler runs on",
            mandatory = True,
        ),
        "urls": attr.string_list(
            doc = "A list of mirror urls containing the tools from the Rust-lang static file server. These must contain the '{}' used to substitute the tool being fetched (using .format).",
            default = DEFAULT_STATIC_RUST_URL_TEMPLATES,
        ),
        "version": attr.string(
            doc = "The version of the tool among \"nightly\", \"beta\", or an exact version.",
            mandatory = True,
        ),
    },
)

def rust_repositories(
        dev_components = False,
        edition = DEFAULT_RUST_EDITION,
        include_rustc_srcs = False,
        iso_date = None,
        prefix_exec = "rules_rust_exec",
        prefix_target = "rules_rust_target",
        register_toolchains = True,
        rustfmt_version = None,
        sha256s = None,
        urls = DEFAULT_STATIC_RUST_URL_TEMPLATES,
        version = DEFAULT_RUST_VERSION):
    """[summary]

    Args:
        version ([type], optional): [description]. Defaults to DEFAULT_RUST_VERSION.
        iso_date ([type], optional): [description]. Defaults to None.
        rustfmt_version ([type], optional): [description]. Defaults to None.
        edition ([type], optional): [description]. Defaults to DEFAULT_RUST_EDITION.
        dev_components (bool, optional): [description]. Defaults to False.
        sha256s ([type], optional): [description]. Defaults to None.
        include_rustc_srcs (bool, optional): [description]. Defaults to False.
        urls ([type], optional): [description]. Defaults to DEFAULT_STATIC_RUST_URL_TEMPLATES.
    """
    if dev_components and version != "nightly":
        fail("Rust version must be set to \"nightly\" to enable rustc-dev components")

    maybe(
        http_archive,
        name = "rules_cc",
        url = "https://github.com/bazelbuild/rules_cc/archive/624b5d59dfb45672d4239422fa1e3de1822ee110.zip",
        sha256 = "8c7e8bf24a2bf515713445199a677ee2336e1c487fa1da41037c6026de04bbc3",
        strip_prefix = "rules_cc-624b5d59dfb45672d4239422fa1e3de1822ee110",
        type = "zip",
    )

    maybe(
        http_archive,
        name = "bazel_skylib",
        sha256 = "1c531376ac7e5a180e0237938a2536de0c54d93f5c278634818e0efc952dd56c",
        urls = [
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.0.3/bazel-skylib-1.0.3.tar.gz",
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.0.3/bazel-skylib-1.0.3.tar.gz",
        ],
    )

    if register_toolchains:
        # Register all default exec triples
        for triple in DEFAULT_TOOLCHAIN_TRIPLES:
            rust_exec_toolchain_repository(
                prefix = prefix_exec,
                version = version,
                edition = edition,
                triple = triple,
                urls = urls,
                iso_date = iso_date,
                dev_components = dev_components,
                sha256s = sha256s,
                include_rustc_srcs = include_rustc_srcs,
            )

        # Register all target triples
        for triple in SUPPORTED_PLATFORM_TRIPLES:
            rust_target_toolchain_repository(
                prefix = prefix_target,
                version = version,
                triple = triple,
                iso_date = iso_date,
                sha256s = sha256s,
                allocator_library = None,
                urls = urls,
                edition = edition,
            )

        native.register_toolchains(str(Label("//rust/private/dummy_cc_toolchain:dummy_cc_wasm32_toolchain")))
