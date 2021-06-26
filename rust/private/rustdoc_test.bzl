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

# buildifier: disable=module-docstring
load("//rust/private:common.bzl", "rust_common")
load("//rust/private:utils.bzl", "find_toolchain", "get_lib_name", "get_preferred_artifact")
load("//util/launcher:launcher.bzl", "create_launcher")

def _rust_doc_test_impl(ctx):
    """The implementation for the `rust_doc_test` rule

    Args:
        ctx (ctx): The rule's context object

    Returns:
        list: A list containing a DefaultInfo provider
    """
    if rust_common.crate_info not in ctx.attr.dep:
        fail("Expected rust library or binary.", "dep")

    crate = ctx.attr.dep[rust_common.crate_info]

    toolchain = find_toolchain(ctx)

    dep_info = ctx.attr.dep[rust_common.dep_info]

    # Construct rustdoc test command, which will be written to a shell script
    # to be executed to run the test.
    flags = _build_rustdoc_flags(dep_info, crate, toolchain)

    # The test script compiles the crate and runs it, so it needs both compile and runtime inputs.
    compile_inputs = depset(
        [crate.output] +
        [toolchain.rust_doc] +
        [toolchain.rustc] +
        toolchain.crosstool_files,
        transitive = [
            crate.srcs,
            dep_info.transitive_libs,
            toolchain.rustc_lib.files,
            toolchain.rust_lib.files,
        ],
    )

    rustdoc = ctx.actions.declare_file(ctx.label.name + toolchain.binary_ext)
    ctx.actions.symlink(
        output = rustdoc,
        target_file = toolchain.rust_doc,
        is_executable = True,
    )

    return create_launcher(
        ctx = ctx,
        args = [
            "--test",
            crate.root.path,
            "--crate-name={}".format(crate.name),
        ] + flags,
        toolchain = toolchain,
        providers = [DefaultInfo(
            runfiles = ctx.runfiles(transitive_files = compile_inputs),
        )],
        executable = rustdoc,
    )

# TODO: Replace with bazel-skylib's `path.dirname`. This requires addressing some dependency issues or
# generating docs will break.
def _dirname(path_str):
    """Returns the path of the direcotry from a unix path.

    Args:
        path_str (str): A string representing a unix path

    Returns:
        str: The parsed directory name of the provided path
    """
    return "/".join(path_str.split("/")[:-1])

def _build_rustdoc_flags(dep_info, crate, toolchain):
    """Constructs the rustdoc script used to test `crate`.

    Args:
        dep_info (DepInfo): The DepInfo provider
        crate (CrateInfo): The CrateInfo provider

    Returns:
        list: A list of rustdoc flags (str)
    """

    d = dep_info

    # nb. Paths must be constructed wrt runfiles, so we construct relative link flags for doctest.
    link_flags = []
    link_search_flags = []

    link_flags.append("--extern=" + crate.name + "=" + crate.output.short_path)
    link_flags += ["--extern=" + c.name + "=" + c.dep.output.short_path for c in d.direct_crates.to_list()]
    link_search_flags += ["-Ldependency={}".format(_dirname(c.output.short_path)) for c in d.transitive_crates.to_list()]

    # Gets the paths to the folders containing the standard library (or libcore)
    rust_lib_files = depset(transitive = [toolchain.rust_lib.files, toolchain.rustc_lib.files])
    rust_lib_paths = depset([file.dirname for file in rust_lib_files.to_list()]).to_list()

    # Tell Rustc where to find the standard library
    link_search_flags.extend(["-L {}".format(lib) for lib in rust_lib_paths])

    # TODO(hlopko): use the more robust logic from rustc.bzl also here, through a reasonable API.
    for lib_to_link in dep_info.transitive_noncrates.to_list():
        is_static = bool(lib_to_link.static_library or lib_to_link.pic_static_library)
        f = get_preferred_artifact(lib_to_link)
        if not is_static:
            link_flags.append("-ldylib=" + get_lib_name(f))
        else:
            link_flags.append("-lstatic=" + get_lib_name(f))
        link_flags.append("-Lnative={}".format(_dirname(f.short_path)))
        link_search_flags.append("-Lnative={}".format(_dirname(f.short_path)))

    edition_flags = ["--edition={}".format(crate.edition)] if crate.edition != "2015" else []

    return link_search_flags + link_flags + edition_flags

rust_doc_test = rule(
    implementation = _rust_doc_test_impl,
    attrs = {
        "dep": attr.label(
            doc = (
                "The label of the target to run documentation tests for.\n" +
                "\n" +
                "`rust_doc_test` can run documentation tests for the source files of " +
                "`rust_library` or `rust_binary` targets."
            ),
            mandatory = True,
            providers = [rust_common.crate_info],
        ),
        "_launcher": attr.label(
            executable = True,
            default = Label("//util/launcher:launcher"),
            cfg = "exec",
            doc = (
                "A launcher executable for loading environment and argument files passed in via the " +
                "`env` attribute and ensuring the variables are set for the underlying test executable."
            ),
        ),
    },
    test = True,
    toolchains = [
        str(Label("//rust:toolchain")),
    ],
    incompatible_use_toolchain_transition = True,
    doc = """Runs Rust documentation tests.

Example:

Suppose you have the following directory structure for a Rust library crate:

```output
[workspace]/
  WORKSPACE
  hello_lib/
      BUILD
      src/
          lib.rs
```

To run [documentation tests][doc-test] for the `hello_lib` crate, define a `rust_doc_test` \
target that depends on the `hello_lib` `rust_library` target:

[doc-test]: https://doc.rust-lang.org/book/documentation.html#documentation-as-tests

```python
package(default_visibility = ["//visibility:public"])

load("@rules_rust//rust:rust.bzl", "rust_library", "rust_doc_test")

rust_library(
    name = "hello_lib",
    srcs = ["src/lib.rs"],
)

rust_doc_test(
    name = "hello_lib_doc_test",
    dep = ":hello_lib",
)
```

Running `bazel test //hello_lib:hello_lib_doc_test` will run all documentation tests for the `hello_lib` library crate.
""",
)
