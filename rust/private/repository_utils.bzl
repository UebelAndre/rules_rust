"""Utility macros for use in rules_rust repository rules"""

load("//rust:known_shas.bzl", "FILE_KEY_TO_SHA")
load(
    "//rust/platform:triple_mappings.bzl",
    "system_to_binary_ext",
    "system_to_dylib_ext",
    "system_to_staticlib_ext",
    "triple_to_constraint_set",
    "triple_to_system",
)

DEFAULT_STATIC_RUST_URL_TEMPLATES = ["https://static.rust-lang.org/dist/{}.tar.gz"]

_build_file_for_compiler_template = """\
load("@rules_rust//rust:toolchain.bzl", "rust_toolchain")

filegroup(
    name = "rustc",
    srcs = ["bin/rustc{binary_ext}"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "rustc_lib",
    srcs = glob(
        [
            "bin/*{dylib_ext}",
            "lib/*{dylib_ext}",
            "lib/rustlib/{target_triple}/codegen-backends/*{dylib_ext}",
            "lib/rustlib/{target_triple}/bin/rust-lld{binary_ext}",
            "lib/rustlib/{target_triple}/lib/*{dylib_ext}",
        ],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "rustdoc",
    srcs = ["bin/rustdoc{binary_ext}"],
    visibility = ["//visibility:public"],
)
"""

def BUILD_for_compiler(target_triple):
    """Emits a BUILD file the compiler `.tar.gz`.

    Args:
        target_triple (str): The triple of the target platform

    Returns:
        str: The contents of a BUILD file
    """
    system = triple_to_system(target_triple)
    return _build_file_for_compiler_template.format(
        binary_ext = system_to_binary_ext(system),
        staticlib_ext = system_to_staticlib_ext(system),
        dylib_ext = system_to_dylib_ext(system),
        target_triple = target_triple,
    )

_build_file_for_cargo_template = """\
load("@rules_rust//rust:toolchain.bzl", "rust_toolchain")

filegroup(
    name = "cargo",
    srcs = ["bin/cargo{binary_ext}"],
    visibility = ["//visibility:public"],
)"""

def BUILD_for_cargo(target_triple):
    """Emits a BUILD file the cargo `.tar.gz`.

    Args:
        target_triple (str): The triple of the target platform

    Returns:
        str: The contents of a BUILD file
    """
    system = triple_to_system(target_triple)
    return _build_file_for_cargo_template.format(
        binary_ext = system_to_binary_ext(system),
    )

_build_file_for_rustfmt_template = """\
load("@rules_rust//rust:toolchain.bzl", "rust_toolchain")

filegroup(
    name = "rustfmt_bin",
    srcs = ["bin/rustfmt{binary_ext}"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "rustfmt",
    srcs = [":rustfmt_bin"],
    visibility = ["//visibility:public"],
)
"""

def BUILD_for_rustfmt(target_triple):
    """Emits a BUILD file the rustfmt `.tar.gz`.

    Args:
        target_triple (str): The triple of the target platform

    Returns:
        str: The contents of a BUILD file
    """
    system = triple_to_system(target_triple)
    return _build_file_for_rustfmt_template.format(
        binary_ext = system_to_binary_ext(system),
    )

_build_file_for_clippy_template = """\
filegroup(
    name = "clippy_driver_bin",
    srcs = ["bin/clippy-driver{binary_ext}"],
    visibility = ["//visibility:public"],
)
"""

def BUILD_for_clippy(target_triple):
    """Emits a BUILD file the clippy `.tar.gz`.

    Args:
        target_triple (str): The triple of the target platform

    Returns:
        str: The contents of a BUILD file
    """
    system = triple_to_system(target_triple)
    return _build_file_for_clippy_template.format(binary_ext = system_to_binary_ext(system))

_build_file_for_stdlib_template = """\
load("@rules_rust//rust:toolchain.bzl", "rust_stdlib_filegroup")

rust_stdlib_filegroup(
    name = "rust_lib-{target_triple}",
    srcs = glob(
        [
            "lib/*.rlib",
            "lib/*{dylib_ext}",
            "lib/*{staticlib_ext}",
        ],
        # Some patterns (e.g. `lib/*.a`) don't match anything, see https://github.com/bazelbuild/rules_rust/pull/245
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)
"""

def BUILD_for_stdlib(target_triple):
    """Emits a BUILD file the stdlib `.tar.gz`.

    Args:
        target_triple (str): The triple of the target platform

    Returns:
        str: The contents of a BUILD file
    """
    system = triple_to_system(target_triple)
    return _build_file_for_stdlib_template.format(
        binary_ext = system_to_binary_ext(system),
        staticlib_ext = system_to_staticlib_ext(system),
        dylib_ext = system_to_dylib_ext(system),
        target_triple = target_triple,
    )

_build_file_for_rustc_srcs_template = """\
filegroup(
    name = "rustc_srcs",
    srcs = glob(["**/*"]),
    visibility = ["//visibility:public"],
)
"""

def BUILD_for_rustc_srcs():
    return _build_file_for_rustc_srcs_template

def load_cargo(ctx):
    """Loads a rustfmt binary and yields corresponding BUILD for it

    Args:
        ctx (repository_ctx): The repository rule's context object

    Returns:
        str: The BUILD file contents for this rustfmt binary
    """
    target_triple = ctx.attr.triple

    if ctx.attr.version in ("beta", "nightly"):
        iso_date = ctx.attr.iso_date
    else:
        iso_date = None

    load_arbitrary_tool(
        ctx,
        iso_date = iso_date,
        target_triple = target_triple,
        tool_name = "cargo",
        tool_subdirectories = ["cargo"],
        version = ctx.attr.version,
        sha256 = ctx.attr.sha256,
    )

    return BUILD_for_cargo(target_triple)

def load_clippy(ctx):
    """Loads a rustfmt binary and yields corresponding BUILD for it

    Args:
        ctx (repository_ctx): The repository rule's context object

    Returns:
        str: The BUILD file contents for this rustfmt binary
    """
    target_triple = ctx.attr.triple

    if ctx.attr.version in ("beta", "nightly"):
        iso_date = ctx.attr.iso_date
    else:
        iso_date = None

    load_arbitrary_tool(
        ctx,
        iso_date = iso_date,
        target_triple = target_triple,
        tool_name = "clippy",
        tool_subdirectories = ["clippy-preview"],
        version = ctx.attr.version,
        sha256 = ctx.attr.sha256,
    )

    # TODO: Clippy should have it's rpath set such that a standalone `rustc` toolchain
    # can be used to provide dependencies needed at runtime. For now, just load another
    # rustc binary with the expectation that Bazel will have cached the artifact and
    # it only needs to be re-extracted.
    return "\n".join([
        load_rust_compiler(ctx),
        BUILD_for_clippy(target_triple),
    ])

def load_rustfmt(ctx):
    """Loads a rustfmt binary and yields corresponding BUILD for it

    Args:
        ctx (repository_ctx): The repository rule's context object

    Returns:
        str: The BUILD file contents for this rustfmt binary
    """
    target_triple = ctx.attr.triple

    if ctx.attr.version in ("beta", "nightly"):
        iso_date = ctx.attr.iso_date
    else:
        iso_date = None

    load_arbitrary_tool(
        ctx,
        iso_date = iso_date,
        target_triple = target_triple,
        tool_name = "rustfmt",
        tool_subdirectories = ["rustfmt-preview"],
        version = ctx.attr.version,
        sha256 = ctx.attr.sha256,
    )

    return BUILD_for_rustfmt(target_triple)

def load_rust_compiler(ctx):
    """Loads a rust compiler and yields corresponding BUILD for it

    Args:
        ctx (repository_ctx): A repository_ctx.

    Returns:
        str: The BUILD file contents for this compiler and compiler library
    """

    target_triple = ctx.attr.triple
    load_arbitrary_tool(
        ctx,
        iso_date = ctx.attr.iso_date,
        target_triple = target_triple,
        tool_name = "rustc",
        tool_subdirectories = ["rustc"],
        version = ctx.attr.version,
    )

    return BUILD_for_compiler(target_triple)

def load_rust_src(ctx):
    """Loads the rust source code. Used by the rust-analyzer rust-project.json generator.

    Args:
        ctx (ctx): A repository_ctx.

    Returns:
        str: The BUILD file contents for this rustc-src artifact
    """
    tool_suburl = produce_tool_suburl("rustc", "src", ctx.attr.version, ctx.attr.iso_date)
    static_rust = ctx.os.environ.get("STATIC_RUST_URL", "https://static.rust-lang.org")
    url = "{}/dist/{}.tar.gz".format(static_rust, tool_suburl)

    tool_path = produce_tool_path("rustc", "src", ctx.attr.version)
    archive_path = tool_path + ".tar.gz"
    sha256s = getattr(ctx.attr, "sha256s", {})
    sha256 = getattr(ctx.attr, "sha256") or sha256s.get(tool_suburl) or FILE_KEY_TO_SHA.get(tool_suburl) or ""
    ctx.download_and_extract(
        url,
        output = ".",
        stripPrefix = tool_path,
        sha256 = sha256,
    )

    return BUILD_for_rustc_srcs()

def load_rust_stdlib(ctx, target_triple):
    """Loads a rust standard library and yields corresponding BUILD for it

    Args:
        ctx (repository_ctx): A repository_ctx.
        target_triple (str): The rust-style target triple of the tool

    Returns:
        str: The BUILD file contents for this stdlib, and a toolchain decl to match
    """

    load_arbitrary_tool(
        ctx,
        iso_date = ctx.attr.iso_date,
        target_triple = target_triple,
        tool_name = "rust-std",
        tool_subdirectories = ["rust-std-{triple}/lib/rustlib/{triple}".format(triple = target_triple)],
        version = ctx.attr.version,
    )

    return BUILD_for_stdlib(target_triple)

def load_rustc_dev_nightly(ctx, target_triple):
    """Loads the nightly rustc dev component

    Args:
        ctx: A repository_ctx.
        target_triple: The rust-style target triple of the tool
    """

    subdir_name = "rustc-dev"
    if ctx.attr.iso_date < "2020-12-24":
        subdir_name = "rustc-dev-{}".format(target_triple)

    load_arbitrary_tool(
        ctx,
        iso_date = ctx.attr.iso_date,
        target_triple = target_triple,
        tool_name = "rustc-dev",
        tool_subdirectories = [subdir_name],
        version = ctx.attr.version,
    )

def load_llvm_tools(ctx, target_triple):
    """Loads the llvm tools

    Args:
        ctx: A repository_ctx.
        target_triple: The rust-style target triple of the tool
    """
    load_arbitrary_tool(
        ctx,
        iso_date = ctx.attr.iso_date,
        target_triple = target_triple,
        tool_name = "llvm-tools",
        tool_subdirectories = ["llvm-tools-preview"],
        version = ctx.attr.version,
    )

def check_version_valid(version, iso_date, param_prefix = ""):
    """Verifies that the provided rust version and iso_date make sense.

    Args:
        version (str): The rustc version
        iso_date (str): The rustc nightly version's iso date
        param_prefix (str, optional): The name of the tool who's version is being checked.
    """

    if not version and iso_date:
        fail("{param_prefix}iso_date must be paired with a {param_prefix}version".format(param_prefix = param_prefix))

    if version in ("beta", "nightly") and not iso_date:
        fail("{param_prefix}iso_date must be specified if version is 'beta' or 'nightly'".format(param_prefix = param_prefix))

    if version not in ("beta", "nightly") and iso_date:
        # buildifier: disable=print
        print("{param_prefix}iso_date is ineffective if an exact version is specified".format(param_prefix = param_prefix))

def serialized_constraint_set_from_triple(target_triple):
    """Returns a string representing a set of constraints

    Args:
        target_triple (str): The target triple of the constraint set

    Returns:
        str: Formatted string representing the serialized constraint
    """
    constraint_set = triple_to_constraint_set(target_triple)
    constraint_set_strs = []
    for constraint in constraint_set:
        constraint_set_strs.append("\"{}\"".format(constraint))
    return "[{}]".format(", ".join(constraint_set_strs))

def produce_tool_suburl(tool_name, target_triple, version, iso_date = None):
    """Produces a fully qualified Rust tool name for URL

    Args:
        tool_name: The name of the tool per static.rust-lang.org
        target_triple: The rust-style target triple of the tool
        version: The version of the tool among "nightly", "beta', or an exact version.
        iso_date: The date of the tool (or None, if the version is a specific version).
    """

    if iso_date:
        return "{}/{}-{}-{}".format(iso_date, tool_name, version, target_triple)
    else:
        return "{}-{}-{}".format(tool_name, version, target_triple)

def produce_tool_path(tool_name, target_triple, version):
    """Produces a qualified Rust tool name

    Args:
        tool_name: The name of the tool per static.rust-lang.org
        target_triple: The rust-style target triple of the tool
        version: The version of the tool among "nightly", "beta', or an exact version.
    """

    return "{}-{}-{}".format(tool_name, version, target_triple)

def load_arbitrary_tool(ctx, tool_name, tool_subdirectories, version, iso_date, target_triple, sha256 = ""):
    """Loads a Rust tool, downloads, and extracts into the common workspace.

    This function sources the tool from the Rust-lang static file server. The index is available at:
    - https://static.rust-lang.org/dist/channel-rust-stable.toml
    - https://static.rust-lang.org/dist/channel-rust-beta.toml
    - https://static.rust-lang.org/dist/channel-rust-nightly.toml

    Args:
        ctx (repository_ctx): A repository_ctx (no attrs required).
        tool_name (str): The name of the given tool per the archive naming.
        tool_subdirectories (str): The subdirectories of the tool files (at a level below the root directory of
            the archive). The root directory of the archive is expected to match
            $TOOL_NAME-$VERSION-$TARGET_TRIPLE.
            Example:
            tool_name
            |    version
            |    |      target_triple
            v    v      v
            rust-1.39.0-x86_64-unknown-linux-gnu/clippy-preview
                                             .../rustc
                                             .../etc
            tool_subdirectories = ["clippy-preview", "rustc"]
        version (str): The version of the tool among "nightly", "beta', or an exact version.
        iso_date (str): The date of the tool (or None, if the version is a specific version).
        target_triple (str): The rust-style target triple of the tool
        sha256 (str, optional): The expected hash of hash of the Rust tool. Defaults to "".
    """

    check_version_valid(version, iso_date, param_prefix = tool_name + "_")

    # N.B. See https://static.rust-lang.org/dist/index.html to find the tool_suburl for a given
    # tool.
    tool_suburl = produce_tool_suburl(tool_name, target_triple, version, iso_date)
    static_rust = ctx.os.environ.get("STATIC_RUST_URL", "https://static.rust-lang.org")
    urls = ["{}/dist/{}.tar.gz".format(static_rust, tool_suburl)]

    for url in getattr(ctx.attr, "urls", DEFAULT_STATIC_RUST_URL_TEMPLATES):
        new_url = url.format(tool_suburl)
        if new_url not in urls:
            urls.append(new_url)

    tool_path = produce_tool_path(tool_name, target_triple, version)
    archive_path = "{}.tar.gz".format(tool_path)
    ctx.download(
        urls,
        output = archive_path,
        sha256 = getattr(ctx.attr, "sha256s", dict()).get(tool_suburl) or
                 FILE_KEY_TO_SHA.get(tool_suburl) or
                 sha256,
    )
    for subdirectory in tool_subdirectories:
        ctx.extract(
            archive_path,
            output = "",
            stripPrefix = "{}/{}".format(tool_path, subdirectory),
        )

    # Cleanup the archive
    ctx.execute(["rm", archive_path])
