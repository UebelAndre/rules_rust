# Copyright 2021 The Bazel Authors. All rights reserved.
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

"""Module containing definitions of all Rust providers."""

CrateInfo = provider(
    doc = "A provider containing general Crate information.",
    fields = {
        "aliases": "Dict[Target, String]: Renamed and aliased crates",
        "cfgs": (
            "List[str]: The set of enabled cfgs for this crate. Note that this field is populated only " +
            "when @rules_rust//rust/settings:collect_cfgs is set."
        ),
        "compile_data": "depset[File]: Compile data required by this crate.",
        "compile_data_targets": "depset[Label]: Compile data targets required by this crate.",
        "data": "depset[File]: Runtime data associated with the target. Not passed to `Rustc` actions, except for `proc-macro` targets where `Rustc` is the runtime.",
        "deps": "depset[DepVariantInfo]: This crate's direct (rust or cc) dependencies' providers.",
        "edition": "str: The edition of this crate.",
        "extra_named_deps": "depset[AliasableDepInfo]: Extra named dependencies.",
        "is_test": "bool: If the crate is being compiled in a test context",
        "metadata": "File: The output from rustc from producing the output file. It is optional.",
        "metadata_supports_pipelining": "bool: If the metadata in 'metadata' (if present) is " +
                                        "usable for pipelined compilation.",
        "name": "str: The name of this crate.",
        "output": "File: The output File that will be produced, depends on crate type.",
        "owner": "Label: The label of the target that produced this CrateInfo",
        "proc_macro_deps": "depset[DepVariantInfo]: This crate's rust proc_macro dependencies' providers.",
        "root": "File: The source File entrypoint to this crate, eg. lib.rs",
        "root_path": "str: If root is a directory, path to the source entrypoint under it.",
        "rustc_env": "Dict[String, String]: Additional `\"key\": \"value\"` environment variables to set for rustc.",
        "rustc_env_files": "[File]: Files containing additional environment variables to set for rustc.",
        "rustc_output": "File: The output from rustc from producing the output file. It is optional.",
        "rustc_rmeta_output": "File: The rmeta file produced for this crate. It is optional.",
        "srcs": "depset[File]: All source Files that are part of the crate.",
        "std_dylib": "File: libstd.so file",
        "type": (
            "str: The type of this crate " +
            "(see [rustc --crate-type](https://doc.rust-lang.org/rustc/command-line-arguments.html#--crate-type-a-list-of-types-of-crates-for-the-compiler-to-emit))."
        ),
        "wrapped_crate_type": (
            "str, optional: The original crate type for targets generated using a previously defined " +
            "crate (typically tests using the `rust_test::crate` attribute)"
        ),
    },
)

DepInfo = provider(
    doc = "A provider containing information about a Crate's dependencies.",
    fields = {
        "dep_env": "File: File with environment variables direct dependencies build scripts rely upon.",
        "direct_crates": "depset[AliasableDepInfo]",
        "link_search_path_files": "depset[File]: All transitive files containing search paths to pass to the linker",
        "transitive_build_infos": "depset[BuildInfo]",
        "transitive_crate_outputs": "depset[File]: All transitive crate outputs.",
        "transitive_crates": "depset[CrateInfo]",
        "transitive_data": "depset[File]: Data of all transitive non-macro dependencies.",
        "transitive_metadata_outputs": "depset[File]: All transitive metadata dependencies (.rmeta, for crates that provide them) and all transitive object dependencies (.rlib) for crates that don't provide metadata.",
        "transitive_noncrates": "depset[LinkerInput]: All transitive dependencies that aren't crates.",
        "transitive_proc_macro_data": "depset[File]: Data of all transitive proc-macro dependencies, and non-macro dependencies of those macros.",
    },
)

CrateGroupInfo = provider(
    doc = "A provider containing a group of crates.",
    fields = {
        "dep_variant_infos": "depset[DepVariantInfo]: Dependency information from all crates in the group.",
    },
)

BuildInfo = provider(
    doc = "A provider containing `rustc` build settings for a given Crate.",
    fields = {
        "bin_link_flags": "Optional[File]: file of binary-scoped `BIN=-Clink-arg=FLAG` records in emission order. Empty BIN applies to all binaries; otherwise matched exactly against `cargo_bin_name`.",
        "cdylib_link_flags": "Optional[File]: file of `-Clink-arg`s to pass to rustc only when the crate is built as a cdylib (`cargo::rustc-cdylib-link-arg`); propagated transitively to cdylibs.",
        "compile_data": "Depset[File]: Compile data provided by the build script that was not copied into `out_dir`.",
        "dep_env": "Optional[File]: extra build script environment variables to be set to direct dependencies.",
        "flags": "Optional[File]: file containing additional flags to pass to rustc",
        "link_search_paths": "Optional[File]: file containing search paths to pass to rustc and linker",
        "linker_flags": "Optional[File]: file containing flags to pass to the linker invoked by rustc or cc_common.link",
        "out_dir": "Optional[File]: directory containing the result of a build script",
        "rustc_env": "Optional[File]: file containing additional environment variables to set for rustc.",
    },
)

DepVariantInfo = provider(
    doc = "A wrapper provider for a dependency of a crate. The dependency can be a Rust " +
          "dependency, in which case the `crate_info` and `dep_info` fields will be populated, " +
          "a Rust build script dependency, in which case `build_info` will be populated, a C/C++" +
          "dependency, in which case `cc_info` will be populated, or a Rust crate group, in which" +
          "case `crate_group_info` will be populated.",
    fields = {
        "build_info": "BuildInfo: The BuildInfo of a Rust dependency",
        "cc_info": "CcInfo: The CcInfo of a C/C++ dependency",
        "crate_group_info": "CrateGroupInfo: The CrateGroupInfo of a Rust crate group dependency",
        "crate_info": "CrateInfo: The CrateInfo of a Rust dependency",
        "dep_info": "DepInfo: The DepInfo of a Rust dependency",
    },
)

AlwaysEnableMetadataOutputGroupsInfo = provider(
    doc = (
        "Enable the 'metadata' and 'rustc_rmeta_output' groups for all targets, " +
        "even if not a library or if pipelining is disabled"
    ),
    fields = {
        "always_enable_metadata_output_groups": ("bool: Whether or not to always enable " +
                                                 "metadata-related output groups"),
    },
)

RustcOutputDiagnosticsInfo = provider(
    doc = (
        "Save json diagnostics from rustc. Json diagnostics are able to be " +
        "consumed by tools such as rust-analyzer to provide IDE integration"
    ),
    fields = {
        "rustc_output_diagnostics": "bool: Whether or not to output diagnostics",
    },
)

StdLibInfo = provider(
    doc = (
        "A collection of files either found within the `rust-stdlib` artifact or " +
        "generated based on existing files."
    ),
    fields = {
        "alloc_files": "List[File]: `.a` files related to the `alloc` module.",
        "between_alloc_and_core_files": "List[File]: `.a` files related to the `compiler_builtins` module.",
        "between_core_and_std_files": "List[File]: `.a` files related to all modules except `adler`, `alloc`, `compiler_builtins`, `core`, and `std`.",
        "core_files": "List[File]: `.a` files related to the `core` and `adler` modules",
        "dot_a_files": "Depset[File]: Generated `.a` files",
        "has_profiler_builtins": "bool: Whether the sysroot contains the profiler_builtins rlib, required for -Cinstrument-coverage.",
        "memchr_files": "Depset[File]: `.a` files associated with the `memchr` module.",
        "panic_files": "Depset[File]: `.a` files associated with `panic_unwind` and `panic_abort`.",
        "self_contained_files": "List[File]: All `.o` files from the `self-contained` directory.",
        "srcs": "List[Target]: All targets from the original `srcs` attribute.",
        "std_dylib": "File: libstd.so file",
        "std_files": "Depset[File]: `.a` files associated with the `std` module.",
        "std_rlibs": "List[File]: All `.rlib` files",
        "test_files": "Depset[File]: `.a` files associated with the `test` module.",
    },
)

# The build settings a `rust_toolchain` reads, by the private attribute that
# carries each. `RustToolchainInfo`'s constructor checks that the rule
# constructing one has these attributes at these labels: the fields it fills
# from them decide how every rustc action behaves, so a toolchain which read
# other settings would compile differently from what the flags on the command
# line say.
RUST_TOOLCHAIN_SETTINGS = {
    "_codegen_units": Label("//rust/settings:codegen_units"),
    "_experimental_compile_rustdoc_tests": Label("//rust/settings:experimental_compile_rustdoc_tests"),
    "_experimental_use_allocator_libraries_with_mangled_symbols_setting": Label("//rust/settings:experimental_use_allocator_libraries_with_mangled_symbols"),
    "_experimental_use_coverage_metadata_files": Label("//rust/settings:experimental_use_coverage_metadata_files"),
    "_experimental_use_global_allocator": Label("//rust/settings:experimental_use_global_allocator"),
    "_incompatible_do_not_include_data_in_compile_data": Label("//rust/settings:incompatible_do_not_include_data_in_compile_data"),
    "_incompatible_do_not_include_transitive_data_in_compile_inputs": Label("//rust/settings:incompatible_do_not_include_transitive_data_in_compile_inputs"),
    "_link_std_dylib_setting": Label("//rust/settings:experimental_link_std_dylib"),
    "_linker_preference": Label("//rust/settings:toolchain_linker_preference"),
    "_no_std": Label("//rust/settings:no_std"),
    "_pipelined_compilation": Label("//rust/settings:pipelined_compilation"),
    "_rename_first_party_crates": Label("//rust/settings:rename_first_party_crates"),
    "_skip_fission_for_rust": Label("//rust/settings:skip_fission_for_rust"),
    "_third_party_dir": Label("//rust/settings:third_party_dir"),
    "_toolchain_generated_sysroot": Label("//rust/settings:toolchain_generated_sysroot"),
}

_RUST_TOOLCHAIN_INFO_FIELDS = {
    "all_files": "Depset[File]: Every file an action running `rustc` needs: the sysroot and `support_files`.",
    "binary_ext": "str: The extension of the binaries `rustc` produces.",
    "cargo": "Optional[File]: The deprecated `rust_toolchain.cargo`, as laid out in the sysroot. Prefer the `cargo_toolchain`.",
    "cargo_clippy": "Optional[File]: The deprecated `rust_toolchain.cargo_clippy`, as laid out in the sysroot. Prefer the `clippy_toolchain`.",
    "channel": "str: The release channel (`stable`, `beta`, `nightly`), or empty.",
    "clippy_driver": "Optional[File]: The deprecated `rust_toolchain.clippy_driver`, as laid out in the sysroot. Prefer the `clippy_toolchain`.",
    "compilation_mode_opts": "Dict[str, struct]: `debug_info`, `opt_level` and `strip_level` by compilation mode (`dbg`, `fastbuild`, `opt`).",
    "coverage_supported": "bool: Whether crates can be instrumented for coverage: `llvm_cov` is set and the standard library carries `profiler_builtins`.",
    "default_edition": "Optional[str]: The edition of crates which do not state one, or `None` when every crate must.",
    "dlltool": "Optional[File]: The `dlltool` `rustc` generates import libraries with.",
    "dylib_ext": "str: The extension of the dynamic libraries `rustc` produces.",
    "env": "Dict[str, str]: Environment variables set in every action.",
    "exec_triple": "struct: The execution platform's triple, as `@rules_rust//rust/platform:triple.bzl` parses it.",
    "extra_exec_rustc_flags": "List[str]: Flags added to `rustc` in the exec configuration, expanded.",
    "extra_rustc_flags": "List[str]: Flags added to `rustc` in the target configuration, expanded.",
    "extra_rustc_flags_for_crate_types": "Dict[str, List[str]]: Flags added to `rustc` by crate type.",
    "iso_date": "str: The date of a `beta` or `nightly` release, or empty.",
    "libstd_and_allocator_ccinfo": "Optional[CcInfo]: The standard library and `allocator_library`, for linking Rust into a `cc_*` target.",
    "libstd_and_global_allocator_ccinfo": "Optional[CcInfo]: The standard library and `global_allocator_library`.",
    "libstd_dylib_and_allocator_ccinfo": "Optional[CcInfo]: The standard library as a dynamic library and `allocator_library`.",
    "libstd_dylib_and_global_allocator_ccinfo": "Optional[CcInfo]: The standard library as a dynamic library and `global_allocator_library`.",
    "linker": "Optional[File]: The explicit linker (`rust_toolchain.linker`), as laid out in the sysroot.",
    "linker_preference": "Optional[str]: `cc`, `rust`, or `None` when nothing stated one.",
    "linker_type": "Optional[str]: `direct`, `indirect`, or `None` to follow `linker_preference`.",
    "llvm_cov": "Optional[File]: `llvm-cov`.",
    "llvm_lib": "List[File]: The `libLLVM` shared objects.",
    "llvm_profdata": "Optional[File]: `llvm-profdata`.",
    "lto": "RustLtoInfo: The link time optimization mode.",
    "make_libstd_and_allocator_ccinfo": "function: Builds a `CcInfo` of the standard library and an allocator library for a rule's own label and actions.",
    "make_variables": "TemplateVariableInfo: `RUSTC`, `RUST_SYSROOT`, `RUST_SYSROOT_SHORT`, `RUST_DEFAULT_EDITION`, and `CARGO`, `RUSTDOC`, `RUSTFMT` where the deprecated attributes are set.",
    "nostd_and_global_allocator_ccinfo": "Optional[CcInfo]: `core` and `alloc` without `std`, and `global_allocator_library`.",
    "per_crate_rustc_flags": "List[str]: Flags added to `rustc` for crates matched by name or path.",
    "require_explicit_unstable_features": "bool: Whether unstable features must be opted into with `-Zallow-features`.",
    "rust_doc": "Optional[File]: The deprecated `rust_toolchain.rust_doc`, as laid out in the sysroot. Prefer the `rustdoc_toolchain`.",
    "rust_objcopy": "Optional[File]: `rust-objcopy`, as laid out in the sysroot.",
    "rust_std": "Depset[File]: The standard library's files, as laid out in the sysroot.",
    "rust_std_dylib": "Optional[File]: The standard library's `libstd` dynamic library.",
    "rust_std_paths": "Depset[str]: The directories of `rust_std`.",
    "rustc": "File: The compiler, as laid out in the sysroot.",
    "rustc_lib": "Depset[File]: The libraries the compiler loads, as laid out in the sysroot.",
    "rustfmt": "Optional[File]: The deprecated `rust_toolchain.rustfmt`, as laid out in the sysroot. Prefer the `rustfmt_toolchain`.",
    "staticlib_ext": "str: The extension of the static libraries `rustc` produces.",
    "stdlib_linkflags": "CcInfo: The flags a C++ linker needs to link the standard library, as a linking context.",
    "support_files": "Depset[File]: The files an action needs besides the sysroot: the standard library's own files, the C++ toolchain and `dlltool`.",
    "sysroot": "str: The path of the sysroot the actions pass to `rustc`.",
    "sysroot_anchor": "File: A file at the root of the sysroot, whose directory is `sysroot`.",
    "sysroot_files": "Depset[File]: The sysroot's tree.",
    "sysroot_short_path": "str: The short path of the sysroot, for actions which run at execution time.",
    "target_abi": "Optional[str]: The target's ABI, from the triple or the target specification.",
    "target_arch": "Optional[str]: The target's architecture, from the triple or the target specification.",
    "target_flag_value": "str: What `--target` is given: the triple, or the path of the target specification.",
    "target_json": "Optional[File]: The custom target specification, when `target_json` is set.",
    "target_os": "Optional[str]: The target's operating system, from the triple or the target specification.",
    "target_triple": "Optional[struct]: The target platform's triple, as `@rules_rust//rust/platform:triple.bzl` parses it, or `None` with `target_json`.",
    "version": "str: The compiler's version, as stated.",
    "version_semver": "Optional[struct]: `version` parsed as `@rules_rust//rust/private:semver.bzl` does, or `None` when it is not a version.",
    "_codegen_units": "int: `--@rules_rust//rust/settings:codegen_units`.",
    "_experimental_compile_rustdoc_tests": "bool: `--@rules_rust//rust/settings:experimental_compile_rustdoc_tests`.",
    "_experimental_use_allocator_libraries_with_mangled_symbols": "int: `rust_toolchain.experimental_use_allocator_libraries_with_mangled_symbols`.",
    "_experimental_use_allocator_libraries_with_mangled_symbols_setting": "bool: `--@rules_rust//rust/settings:experimental_use_allocator_libraries_with_mangled_symbols`.",
    "_experimental_use_cc_common_link": "bool: Whether binaries are linked with `cc_common.link`.",
    "_experimental_use_coverage_metadata_files": "bool: `--@rules_rust//rust/settings:experimental_use_coverage_metadata_files`.",
    "_experimental_use_global_allocator": "bool: `--@rules_rust//rust/settings:experimental_use_global_allocator`.",
    "_incompatible_do_not_include_data_in_compile_data": "bool: `--@rules_rust//rust/settings:incompatible_do_not_include_data_in_compile_data`.",
    "_incompatible_do_not_include_transitive_data_in_compile_inputs": "bool: `--@rules_rust//rust/settings:incompatible_do_not_include_transitive_data_in_compile_inputs`.",
    "_link_std_dylib": "bool: Whether the standard library is linked dynamically.",
    "_no_std": "str: `--@rules_rust//rust/settings:no_std`.",
    "_pipelined_compilation": "bool: `--@rules_rust//rust/settings:pipelined_compilation`.",
    "_rename_first_party_crates": "bool: `--@rules_rust//rust/settings:rename_first_party_crates`.",
    "_skip_fission_for_rust": "bool: `--@rules_rust//rust/settings:skip_fission_for_rust`.",
    "_third_party_dir": "str: `--@rules_rust//rust/settings:third_party_dir`.",
    "_toolchain_generated_sysroot": "bool: `--@rules_rust//rust/settings:toolchain_generated_sysroot`.",
}

def _rust_toolchain_info_init(*, ctx, **fields):
    """Checks that the rule constructing a `RustToolchainInfo` reads the settings its fields stand for.

    Args:
        ctx (ctx): The context of the rule constructing the provider.
        **fields: The provider's fields.

    Returns:
        dict: The fields.
    """
    for name, setting in RUST_TOOLCHAIN_SETTINGS.items():
        target = getattr(ctx.attr, name, None)
        if target == None:
            fail("{}: only a rule with the attribute `{}` (defaulting to `{}`) can construct a `RustToolchainInfo`".format(
                ctx.label,
                name,
                setting,
            ))
        if target.label != setting:
            fail("{}: only a rule whose `{}` is `{}` can construct a `RustToolchainInfo`; here it is `{}`".format(
                ctx.label,
                name,
                setting,
                target.label,
            ))
    return fields

RustToolchainInfo, _new_rust_toolchain_info = provider(
    doc = (
        "A Rust toolchain: the compiler, the standard library and the settings the actions " +
        "which run them follow. `rust_toolchain` returns one and carries it on the " +
        "`ToolchainInfo` it registers as `rust_toolchain_info`, beside the same fields; " +
        "`@rules_rust//rust/private:utils.bzl%find_toolchain` returns it for a rule which " +
        "resolved `@rules_rust//rust:toolchain_type`. The constructor takes `ctx` and fails " +
        "unless the rule's private attributes are the build settings in " +
        "`RUST_TOOLCHAIN_SETTINGS`."
    ),
    fields = _RUST_TOOLCHAIN_INFO_FIELDS,
    init = _rust_toolchain_info_init,
)

def rust_toolchain_info_fields(info):
    """The fields of a `RustToolchainInfo`, by name.

    Args:
        info (RustToolchainInfo): The provider.

    Returns:
        dict: Each field's value, for a `ToolchainInfo` which carries the same data.
    """
    return {field: getattr(info, field) for field in _RUST_TOOLCHAIN_INFO_FIELDS}

CaptureClippyOutputInfo = provider(
    doc = "Value of the `capture_clippy_output` build setting",
    fields = {"capture_output": "Value of the `capture_clippy_output` build setting"},
)

ClippyOutputDiagnosticsInfo = provider(
    doc = "Value of the `clippy_output_diagnostics` build setting",
    fields = {"output_diagnostics": "Value of the `clippy_output_diagnostics` build setting"},
)

ClippyInfo = provider(
    doc = "Provides information on a clippy run.",
    fields = {
        "output": "File with the clippy output.",
    },
)

TestCrateInfo = provider(
    doc = "A wrapper around a CrateInfo. " +
          "Certain rule types, like rust_static_library and rust_shared_library " +
          "are not intended for consumption by other Rust targets, and should not " +
          "provide a CrateInfo. However, one should still be able to write a rust_test " +
          "for them. Thus, we create a CrateInfo, but do not advertise it as such, " +
          "but rather through this provider, that rust_test understands.",
    fields = {
        "crate": "CrateInfo: The underlying CrateInfo of the dependency",
    },
)

RustAnalyzerInfo = provider(
    doc = "RustAnalyzerInfo holds rust crate metadata for targets",
    fields = {
        "aliases": "Dict[RustAnalyzerInfo, String]: Replacement names these targets should be known as in Rust code",
        "build_info": "BuildInfo: build info for this crate if present",
        "build_info_out_dirs": "Depset[File]: transitive closure of build script out dirs",
        "cfgs": "List[String]: features or other compilation `--cfg` settings",
        "crate": "CrateInfo: Crate information.",
        "crate_specs": "Depset[File]: transitive closure of crate spec files",
        "deps": "List[RustAnalyzerInfo]: direct dependencies",
        "env": "Dict[String: String]: Environment variables, used for the `env!` macro",
        "proc_macro_dylib": "File: if this is a proc-macro target, the shared library output",
        "proc_macro_dylibs": "Depset[File]: transitive closure of proc-macro shared library files",
    },
)

RustAnalyzerGroupInfo = provider(
    doc = "RustAnalyzerGroupInfo holds multiple RustAnalyzerInfos",
    fields = {
        "deps": "List[RustAnalyzerInfo]: direct dependencies",
    },
)

LintsInfo = provider(
    doc = "LintsInfo holds the 'allow', 'warn', etc. config for rustc, clippy, and rustdoc lints.",
    fields = {
        "clippy_lint_files": "List[File]: files with rustc args for clippy targets.",
        "clippy_lint_flags": "List[String]: rustc flags to specify when building clippy targets.",
        "rustc_lint_files": "List[File]: list of files with rustc flags to specify when building rust_* targets.",
        "rustc_lint_flags": "List[String]: rustc flags to specify when building rust_* targets.",
        "rustdoc_lint_files": "List[File]: files with rustc args for rustdoc target.",
        "rustdoc_lint_flags": "List[String]: rustc flags to specify when building rust_doc targets.",
    },
)

AllocatorLibrariesInfo = provider(
    doc = "AllocatorLibrariesInfo provides allocator libraries for linking rust code with a non-rust linker.",
    fields = {
        "allocator_library": "Optional[CcInfo]: used when the default rust allocator is used",
        "global_allocator_library": "Optional[CcInfo]: used when a global rust allocator is used",
        "libstd_and_allocator_ccinfo": "Optional[CcInfo]: used when the default rust allocator is used",
        "libstd_and_global_allocator_ccinfo": "Optional[CcInfo]: used when a global rust allocator is used",
        "libstd_dylib_and_allocator_ccinfo": "Optional[CcInfo]: used when the default rust allocator is used with a dylib stdlib",
        "libstd_dylib_and_global_allocator_ccinfo": "Optional[CcInfo]: used when a global rust allocator is used with a dylib stdlib",
        "nostd_and_global_allocator_ccinfo": "Optional[CcInfo]: used when nostd with a global rust allocator is used",
    },
)

AllocatorLibrariesImplInfo = provider(
    doc = "AllocatorLibrariesImplInfo provides the rust-generated linker input for linking rust code with a non-rust linker.",
    fields = {
        "static_archive": "Optional[File]: the allocator library archive (typically .a file).",
    },
)

UnstableRustFeaturesInfo = provider(
    doc = "UnstableRustFeaturesInfo contains a function mapping build targets to unstable features approved for use. Only works on nightly toolchains. May return the special value \"__all__\" to allow all unstable features for the target.",
    fields = {"unstable_rust_features_config": "Callable[[Label], List[string]] Returns a list of unstable features approved for use for the given build target."},
)
