"""Bazel test rules for [wasm-bindgen](https://crates.io/crates/wasm-bindgen)"""

load("@rules_rust//rust:defs.bzl", "rust_common")

# buildifier: disable=bzl-visibility
load("@rules_rust//rust/private:rust.bzl", "get_rust_test_flags")

# buildifier: disable=bzl-visibility
load("@rules_rust//rust/private:rustc.bzl", "rustc_compile_action")

# buildifier: disable=bzl-visibility
# load("@rules_rust//rust/private:toolchain_utils.bzl", "get_coverage_env")

# buildifier: disable=bzl-visibility
load(
    "@rules_rust//rust/private:utils.bzl",
    "determine_output_hash",
    "expand_dict_value_locations",
    "find_toolchain",
    "generate_output_diagnostics",
    "get_import_macro_deps",
    "transform_deps",
    "transform_sources",
)
load("//private:transitions.bzl", "wasm_bindgen_transition")

def _rlocationpath(file, workspace_name):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

def _rust_wasm_bindgen_test_impl(ctx):
    wb_toolchain = ctx.toolchains[Label("//wasm_bindgen:toolchain_type")]
    if not wb_toolchain.webdriver or not wb_toolchain.browser:
        fail("The currently registered wasm_bindgen_toolchain does not have a webdriver or browser assigned. Tests are unavailable without one.")

    toolchain = find_toolchain(ctx)

    crate_type = "bin"
    deps = transform_deps(ctx.attr.deps)
    proc_macro_deps = transform_deps(ctx.attr.proc_macro_deps + get_import_macro_deps(ctx))

    if ctx.attr.crate and ctx.attr.srcs:
        fail("rust_test.crate and rust_test.srcs are mutually exclusive. Update {} to use only one of these attributes".format(
            ctx.label,
        ))

    # Target is building the crate in `test` config
    crate = ctx.attr.crate[rust_common.crate_info] if rust_common.crate_info in ctx.attr.crate else ctx.attr.crate[rust_common.test_crate_info].crate

    output_hash = determine_output_hash(crate.root, ctx.label)
    output = ctx.actions.declare_file(
        "test-%s/%s%s" % (
            output_hash,
            ctx.label.name,
            toolchain.binary_ext,
        ),
    )

    srcs, crate_root = transform_sources(ctx, ctx.files.srcs, getattr(ctx.file, "crate_root", None))

    # Optionally join compile data
    if crate.compile_data:
        compile_data = depset(ctx.files.compile_data, transitive = [crate.compile_data])
    else:
        compile_data = depset(ctx.files.compile_data)
    if crate.compile_data_targets:
        compile_data_targets = depset(ctx.attr.compile_data, transitive = [crate.compile_data_targets])
    else:
        compile_data_targets = depset(ctx.attr.compile_data)
    rustc_env_files = ctx.files.rustc_env_files + crate.rustc_env_files

    # crate.rustc_env is already expanded upstream in rust_library rule implementation
    rustc_env = dict(crate.rustc_env)
    data_paths = depset(direct = getattr(ctx.attr, "data", [])).to_list()
    rustc_env.update(expand_dict_value_locations(
        ctx,
        ctx.attr.rustc_env,
        data_paths,
    ))

    # Build the test binary using the dependency's srcs.
    crate_info_dict = dict(
        name = crate.name,
        type = crate_type,
        root = crate.root,
        srcs = depset(srcs, transitive = [crate.srcs]),
        deps = depset(deps, transitive = [crate.deps]),
        proc_macro_deps = depset(proc_macro_deps, transitive = [crate.proc_macro_deps]),
        aliases = {},
        output = output,
        rustc_output = generate_output_diagnostics(ctx, output),
        edition = crate.edition,
        rustc_env = rustc_env,
        rustc_env_files = rustc_env_files,
        is_test = True,
        compile_data = compile_data,
        compile_data_targets = compile_data_targets,
        wrapped_crate_type = crate.type,
        owner = ctx.label,
    )

    crate_providers = rustc_compile_action(
        ctx = ctx,
        attr = ctx.attr,
        toolchain = toolchain,
        crate_info_dict = crate_info_dict,
        rust_flags = get_rust_test_flags(ctx.attr),
        skip_expanding_rustc_env = True,
    )
    data = getattr(ctx.attr, "data", [])

    env = expand_dict_value_locations(
        ctx,
        getattr(ctx.attr, "env", {}),
        data,
    )

    # if ctx.configuration.coverage_enabled:
    #     env.update(get_coverage_env(toolchain))

    components = "{}/{}".format(ctx.label.workspace_root, ctx.label.package).split("/")
    env["CARGO_MANIFEST_DIR"] = "/".join([c for c in components if c])

    runner = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = runner,
        target_file = ctx.executable._runner,
        is_executable = True,
    )

    env["BROWSER"] = _rlocationpath(ctx, wb_toolchain.browser)
    if wb_toolchain.browser_type == "chrome":
        env["CHROMEDRIVER"] = _rlocationpath(ctx, wb_toolchain.webdriver)
    elif wb_toolchain.browser_type == "firefix":
        env["GECKODRIVER"] = _rlocationpath(ctx, wb_toolchain.webdriver)
    else:
        fail("Unepxected browser type: {}".format(wb_toolchain.browser_type))

    providers = []

    for prov in crate_providers:
        if type(prov) == "DefaultInfo":
            env["TEST_WASM_BINARY"] = _rlocationpath(ctx, prov.files_to_run.executable)
            providers.append(DefaultInfo(
                files = prov.files,
                runfiles = prov.default_runfiles.merge(
                    files = wb_toolchain.all_files,
                ),
                executable = runner,
            ))
        else:
            providers.append(prov)

    providers.append(testing.TestEnvironment(env))

    return providers

rust_wasm_bindgen_test = rule(
    doc = "Rules for running [wasm-bindgen tests](https://rustwasm.github.io/wasm-bindgen/wasm-bindgen-test/index.html).",
    implementation = _rust_wasm_bindgen_test_impl,
    cfg = wasm_bindgen_transition,
    attrs = {
        "crate": attr.label(
            doc = "TODO",
            providers = [rust_common.crate_info],
            mandatory = True,
        ),
        "webdriver": attr.string(
            doc = "TODO",
            values = [
                "chrome",
                "firefox",
            ],
        ),
        "_runner": attr.label(
            doc = "TODO",
            cfg = "exec",
            executable = True,
            default = Label("//private:wasm_bindgen_test_runner"),
        ),
    },
    test = True,
)
