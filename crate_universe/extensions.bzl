"""# Crate Universe

Crate Universe is a set of Bazel rule for generating Rust targets using Cargo.

This doc describes using crate_universe with bzlmod.

If you're using a WORKSPACE file, please see [the WORKSPACE equivalent of this doc](crate_universe_workspace.html).

There are some examples of using crate_universe with bzlmod in the [example folder](https://github.com/bazelbuild/rules_rust/tree/main/examples).

# Table of Contents

1. [Setup](#Setup)
2. [Dependencies](#dependencies)
    * [Cargo Workspace](#cargo-workspaces)
    * [Direct Packages](#direct-dependencies)
    * [Binary Dependencies](#binary-dependencies)
    * [Vendored Dependencies](#vendored-dependencies)
3. [Crate reference](#crate)
   * [from_cargo](#from_cargo)
   * [from_specs](#from_specs)


## Setup

To use rules_rust in a project using bzlmod, add the following to your MODULE.bazel file:

```python
bazel_dep(name = "rules_rust", version = "0.75.0")
```

You find the latest version on the [release page](https://github.com/bazelbuild/rules_rust/releases).


After adding `rules_rust` in your `MODULE.bazel`, set the following to begin using `crate_universe`:

```python
crate = use_extension("@rules_rust//crate_universe:extensions.bzl", "crate")
//  # ... Dependencies
use_repo(crate, "crates")
```

## Dependencies

There are four different ways to declare dependencies in your MODULE.

1) Cargo manifests
2) Direct Dependencies
3) Binary Dependencies
4) Vendored Dependencies

Prefer a Cargo manifest. Everything Cargo can express about a dependency (features, targets,
renames, `[patch]`, registries, workspace inheritance, ...) is available in a `Cargo.toml`, and
Cargo tooling keeps working against it. The `spec` tags cover the simple cases only.

### Cargo manifests

Structure your project as a Cargo workspace, or write a `Cargo.toml` which only declares the
dependencies, and `from_cargo` resolves it and generates Bazel dependencies from there.
You find a complete example in the in the [example folder](https://github.com/bazelbuild/rules_rust/tree/main/examples/all_crate_deps).

```python
crate = use_extension("@rules_rust//crate_universe:extensions.bzl", "crate")

crate.from_cargo(
    name = "crates",
    cargo_lockfile = "//:Cargo.lock",
    manifests = ["//:Cargo.toml"],
)
use_repo(crate, "crates")
```

#### Note if using Private Crate Registries

If you are using from_cargo and are pulling dependencies from a private crate registry such as Artifactory,
make sure you set the `CARGO_BAZEL_ISOLATED=false bazel build //...` environmental.  If not `crates_universe`
will not be able to pull from your private registry.

The generated crates_repository contains helper macros which make collecting dependencies for Bazel targets simpler.
Notably, the all_crate_deps, aliases, and crate_edition macros (
see [Dependencies API](https://bazelbuild.github.io/rules_rust/crate_universe_workspace.html#dependencies-api)) commonly allow the
Cargo.toml files to be the single source of truth for dependencies.
Since these macros come from the generated repository, the dependency labels,
alias definitions, and editions they return will automatically update BUILD targets. In your BUILD files,
you use these macros for a Rust library as shown below:

```python
load("@crates//:defs.bzl", "aliases", "all_crate_deps", "crate_edition")
load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

rust_library(
    name = "lib",
    aliases = aliases(),
    edition = crate_edition(),
    deps = all_crate_deps(
        normal = True,
    ),
    proc_macro_deps = all_crate_deps(
        proc_macro = True,
    ),
)

rust_test(
    name = "unit_test",
    crate = ":lib",
    aliases = aliases(
        normal_dev = True,
        proc_macro_dev = True,
    ),
    edition = crate_edition(),
    deps = all_crate_deps(
        normal_dev = True,
    ),
    proc_macro_deps = all_crate_deps(
        proc_macro_dev = True,
    ),
)
```

For a Rust binary that does not depend on any macro, use the following configuration
in your build file:

```python
rust_binary(
    name = "bin",
    srcs = ["src/main.rs"],
    edition = crate_edition(),
    deps = all_crate_deps(normal = True),
)
```

You have to repin before your first build to ensure all Bazel targets for the macros
are generated.

Dependency syncing and updating is done in the repository rule which means it's done during the
analysis phase of builds. As mentioned in the environments variable table above, the `CARGO_BAZEL_REPIN`
(or `REPIN`) environment variables can be used to force the rule to update dependencies and potentially
render a new lockfile. Given an instance of this repository rule named `crates`, the easiest way to
repin dependencies is to run:

```shell
CARGO_BAZEL_REPIN=1 bazel sync --only=crates
```

This will result in all dependencies being updated for a project. The `CARGO_BAZEL_REPIN`
environment variable can also be used to customize how dependencies are updated.
For more details about repin, [please refer to the documentation](https://bazelbuild.github.io/rules_rust/crate_universe_workspace.html#crates_vendor).

### Dependency modules

A module consumed as a dependency declares its repositories the same way. `from_cargo` is
the normal form: the module ships its `Cargo.lock`, and the consumer uses the module's
`cargo-bazel-lock.json` as it is when one is shipped and readable, or otherwise resolves
the repository itself as Cargo would, honoring the `Cargo.lock`. Either way the consumer
reads files of the module, so its archive is fetched once per module version, which a
consumer building any of its targets pays regardless.

A `from_specs` repository with neither `lockfile` nor `cargo_lockfile` has every input in
`MODULE.bazel`, which Bazel reads from the registry, so a consumer resolves it without
fetching the module's archive at all. This suits modules which exist to provide crates
rather than targets. Pin exact versions in such specs: the consumer resolves the rest.

### Direct Dependencies

In cases where Rust targets have heavy interactions with other Bazel targets ([Cc](https://docs.bazel.build/versions/main/be/c-cpp.html), [Proto](https://rules-proto-grpc.com/en/4.5.0/lang/rust.html),
etc.), maintaining Cargo.toml files may have diminishing returns as things like rust-analyzer
begin to be confused about missing targets or environment variables defined only in Bazel.
In situations like this, it may be desirable to have a "Cargo free" setup. You find an example in the in the [example folder](https://github.com/bazelbuild/rules_rust/tree/main/examples/hello_world_no_cargo).

For simple sets of dependencies, `spec` tags describe them directly, as shown below. A `spec`
cannot express everything a `Cargo.toml` can; when one is not enough, write a manifest which
only declares the dependencies and use `from_cargo` with it instead.

```python
crate = use_extension("@rules_rust//crate_universe:extensions.bzl", "crate")

crate.spec(package = "serde", features = ["derive"], version = "1.0")
crate.spec(package = "serde_json", version = "1.0")
crate.spec(package = "tokio", default_features = False, features = ["macros", "net", "rt-multi-thread"], version = "1.38")

crate.from_specs()
use_repo(crate, "crates")
```

Consuming dependencies may be more ergonomic in this case through the aliases defined in the new repository.
In your BUILD files, you use direct dependencies as shown below:

```python
rust_binary(
    name = "bin",
    crate_root = "src/main.rs",
    srcs = glob([
        "src/*.rs",
    ]),
    deps = [
        # External crates
        "@crates//serde",
        "@crates//serde_json",
        "@crates//tokio",
    ],
    visibility = ["//visibility:public"],
)
```

Notice, direct dependencies do not need repining.
Only a cargo workspace needs updating whenever the underlying Cargo.toml file changed.

### License metadata

Every generated crate declares its identity and license as Bazel `package_metadata`, through
[rules_license](https://github.com/bazelbuild/rules_license): a `package_info` with the crate's
name, version, URL and `purl`, and a `license` with the SPDX kinds of its license expression and
its license text when it ships one. Tools which gather metadata over a dependency graph, SBOM
generators for example, see them without configuration. Each hub subpackage aliases them next to
the crate, so `@crates//serde:license` and `@crates//serde:package_info` name serde's.
`render_config(generate_rules_license_metadata = False)` turns this off.

### Binary Dependencies

With cargo you `can install` binary dependencies (bindeps) as well with `cargo install` command.

We don't have such easy facilities available in bazel besides specifying it as a dependency.
To mimic cargo's bindeps feature we use the unstable feature called [artifact-dependencies](https://doc.rust-lang.org/nightly/cargo/reference/unstable.html?highlight=feature#artifact-dependencies)
which integrates well with bazel concepts.

You could use the syntax specified in the above document to place it in `Cargo.toml`. For that you can consult the following [example](https://github.com/bazelbuild/rules_rust/blob/main/crate_universe/tests/integration/cargo_bindeps/MODULE.bazel).

This method has the following consequences:
* if you use shared dependency tree with your project these binary dependencies will interfere with yours (may conflict)
* you have to resolve with a nightly Cargo, because `-Zbindeps` is unstable: name one with
  `crate.host_tools` (see below)

Alternatively you can specify this in a separate `repo` with `cargo.from_specs` syntax:

```python
bindeps = use_extension("@rules_rust//crate_universe:extensions.bzl", "crate")

bindeps.spec(package = "cargo-machete", version = "=0.7.0", artifact = "bin")
bindeps.annotation(crate = "cargo-machete", gen_all_binaries = True)

bindeps.host_tools(
  cargo = "@rust_host_tools_nightly//:bin/cargo",
  rustc = "@rust_host_tools_nightly//:bin/rustc",
)

bindeps.from_specs(
  name = "bindeps",
)

use_repo(bindeps, "bindeps")
```

You can run the specified binary dependency with the following command or create additional more complex rules on top of it.

```bash
bazel run @bindeps//:cargo-machete__cargo-machete
```

Notice, direct dependencies do not need repining.
Only a cargo workspace needs updating whenever the underlying Cargo.toml file changed.

### Vendored Dependencies

In some cases, it is require that all external dependencies are vendored, meaning downloaded
and stored in the workspace. This helps, for example, to conduct licence scans, apply custom patches,
or to ensure full build reproducibility since no download error could possibly occur.
You find a complete example in the in the [example folder](https://github.com/bazelbuild/rules_rust/tree/main/examples/all_deps_vendor).

For the setup, you need to add the skylib in addition to the rust rules to your `MODULE.bazel`.

```python
module(
    name = "deps_vendored",
    version = "0.0.0"
)
###############################################################################
# B A Z E L  C E N T R A L  R E G I S T R Y # https://registry.bazel.build/
###############################################################################
# https://github.com/bazelbuild/bazel-skylib/releases/
bazel_dep(name = "bazel_skylib", version = "1.8.2")

# https://github.com/bazelbuild/rules_rust/releases
bazel_dep(name = "rules_rust", version = "0.75.0")

###############################################################################
# T O O L C H A I N S
###############################################################################

# Rust toolchain
RUST_EDITION = "2021"
RUST_VERSION = "1.80.1"

rust = use_extension("@rules_rust//rust:extensions.bzl", "rust")
rust.toolchain(
    edition = RUST_EDITION,
    versions = [RUST_VERSION],
)
use_repo(rust, "rust_toolchains")
register_toolchains("@rust_toolchains//:all")

###############################################################################
# R U S T  C R A T E S
###############################################################################
crate = use_extension("@rules_rust//crate_universe:extensions.bzl", "crate")
```

Note, it is important to load the crate_universe rules otherwise you will get an error
as the rule set is needed in the vendored target.

Assuming you have a package called `basic` in which you want to vendor dependencies,
then you create a folder `basic/3rdparty`. The folder name can be arbitrary,
but by convention, its either thirdparty or 3rdparty to indicate vendored dependencies.
In the 3rdparty folder, you add a target crates_vendor to declare your dependencies to vendor.
In the example, we vendor a specific version of bzip2.

```python
load("@rules_rust//crate_universe:defs.bzl", "crate", "crates_vendor")

crates_vendor(
    name = "crates_vendor",
    annotations = {
        "bzip2-sys": [crate.annotation(
            gen_build_script = True,
        )],
    },
    cargo_lockfile = "Cargo.Bazel.lock",
    generate_build_scripts = False,
    mode = "remote",
    packages = {
        "bzip2": crate.spec(
            version = "=0.3.3",
        ),
    },
    repository_name = "basic",
    tags = ["manual"],
)
```

Next, you have to run `Cargo build` to generate a Cargo.lock file with all resolved dependencies.
Then, you rename Cargo.lock to Cargo.Bazel.lock and place it inside the `basic/3rdparty` folder.

At this point, you have the following folder and files:

```
basic
    |-- 3rdparty
    |   |-- BUILD.bazel
    |   |-- Cargo.Bazel.lock
```

Now you can run the `crates_vendor` target:

`bazel run //basic/3rdparty:crates_vendor`

This generates a crate folders with all configurations for the vendored dependencies.

```
basic
    |-- 3rdparty
    |   |-- cratea
    |   |-- BUILD.bazel
    |   |-- Cargo.Bazel.lock
```

Suppose you have an application in `basic/src` that is defined in `basic/BUILD.bazel` and
that depends on a vendored dependency. The vendored crates are exposed through the hub
repository named by `repository_name` (`basic_sys` here), one subpackage per crate. You
declare a vendored dependency in your target as follows:

```python
load("@rules_rust//rust:defs.bzl", "rust_binary")

rust_binary(
    name = "hello_sys",
    srcs = ["src/main.rs"],
    deps = ["@basic_sys//bzip2"],
    visibility = ["//visibility:public"],
)
```
Note, the vendored dependency is not yet accessible because you have to define first
how to load the vendored dependencies. For that, you first create a file `sys_deps.bzl`
and add the following content:

```python
# rename the default name "crate_repositories" in case you import multiple vendored folders.
load("//basic/3rdparty/crates:defs.bzl", basic_crate_repositories = "crate_repositories")

def sys_deps():
    # Load the vendored dependencies
    basic_crate_repositories()
```

This is straightforward, you import the generated crate_repositories from the crates folder,
rename it to avoid name clashes in case you import from multiple vendored folders, and then
just load the vendored dependencies.

In a WORKSPACE configuration, you would just load and call sys_deps(), but in a MODULE configuration, you cannot do that.
Instead, you create a new file `WORKSPACE.bzlmod` and add the following content.

```python
load("//:sys_deps.bzl", "sys_deps")
sys_deps()
```

Now, you can build the project as usual.

There are some more examples of using crate_universe with bzlmod in the [example folder](https://github.com/bazelbuild/rules_rust/blob/main/examples/).

"""

load("@bazel_features//:features.bzl", "bazel_features")
load("@bazel_skylib//lib:structs.bzl", "structs")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load(
    "//crate_universe/private:common_utils.bzl",
    "LOCKFILE_MODES",
    "LOCKFILE_MODE_DOC",
    "is_within_workspace",
    "new_cargo_bazel_fn",
)
load("//crate_universe/private:crate.bzl", _crate_universe_crate = "crate")
load(
    "//crate_universe/private:crates_vendor.bzl",
    "CRATES_VENDOR_ATTRS",
    "crates_vendor_remote_repository",
    "generate_config_file",
    "generate_splicing_manifest",
)
load(
    "//crate_universe/private:generate_utils.bzl",
    "CARGO_BAZEL_GENERATOR_SHA256",
    "CARGO_BAZEL_GENERATOR_URL",
    "CRATES_REPOSITORY_ENVIRON",
    "GENERATOR_ENV_VARS",
    "determine_repin",
    "execute_generator",
    "lockfile_is_readable",
    generate_render_config = "render_config",
)
load("//crate_universe/private:local_crate_mirror.bzl", "local_crate_mirror")
load(
    "//crate_universe/private:splicing_utils.bzl",
    "splice_workspace_manifest",
    generate_splicing_config = "splicing_config",
)
load("//crate_universe/private:urls.bzl", "CARGO_BAZEL_SHA256S", "CARGO_BAZEL_URLS")
load("//rust/platform:triple.bzl", "get_host_triple")
load("//rust/platform:triple_mappings.bzl", "SUPPORTED_PLATFORM_TRIPLES", "system_to_binary_ext")

# buildifier: disable=bzl-visibility
load("//rust/private:repositories.bzl", "DEFAULT_TOOLCHAIN_TRIPLES", "cargo_tools_repository_name")

_OPT_BOOL_VALUES = {
    "auto": None,
    "off": False,
    "on": True,
}

def _get_or_insert(d, key, value):
    if key not in d:
        d[key] = value
    return d[key]

def _annotations_for_repo(global_annotations, module_annotations, repo_specific_annotations):
    """Merges the annotations which apply to a repository, broadest scope first.

    Args:
        global_annotations (dict): The root module's `repositories = ["*"]` annotations, keyed by crate.
        module_annotations (dict): The annotations of the repository's own module, keyed by crate.
        repo_specific_annotations (dict): The annotations naming this repository, keyed by crate.

    Returns:
        dict: The merged annotations, keyed by crate.
    """
    annotations = {}
    for scoped in [global_annotations, module_annotations, repo_specific_annotations]:
        for crate, values in (scoped or {}).items():
            _get_or_insert(annotations, crate, []).extend(values)
    return annotations

# Render settings which describe the build rather than one hub. They reach every
# crate's BUILD file, so they must agree across hubs for crates to be shared, and
# they must match the platforms and toolchains the build registers. The root
# module sets them for the whole build with `render_config(repositories = ["*"])`.
_BUILD_WIDE_RENDER_SETTINGS = [
    "generate_cargo_toml_env_vars",
    "generate_rules_license_metadata",
    "platforms_template",
]

def _is_global(tag):
    return list(tag.repositories) == ["*"]

def _canonical_platforms_template(template):
    """Rewrites `platforms_template` so it resolves the same way from every generated repository.

    The template is written verbatim into the BUILD files of hubs and pooled crates, whose
    repository mapping is rules_rust's, not the root module's. A label of the main repository
    (`//platforms:{triple}`) therefore has to be spelled with its canonical, empty repository name,
    and `@rules_rust//...` is resolved through rules_rust's own mapping.

    Args:
        template (str): The template as the root module wrote it.

    Returns:
        str: The template with a canonical repository.
    """

    # buildifier: disable=canonical-repository
    if template.startswith("@@"):
        return template
    if template.startswith("//"):
        # buildifier: disable=canonical-repository
        return "@@" + template
    if template.startswith("@rules_rust//"):
        placeholder = "__triple__"
        return str(Label(template.replace("{triple}", placeholder))).replace(placeholder, "{triple}")
    fail(("`platforms_template` `{}` cannot be resolved from the repositories crate_universe generates. " +
          "Point it at a package of the main repository (`//platforms:{{triple}}`) or use a canonical " +
          # buildifier: disable=canonical-repository
          "label (`@@...`).").format(template))

# Render settings whose default for extension-generated repositories differs
# from `render_config()`'s. The generated BUILD files resolve `@rules_license`
# through rules_rust's own repository mapping, so license metadata costs the
# module nothing; `crates_vendor` output lives in the module's workspace, where
# it would need `rules_license` as a dependency, and so keeps opting in.
_EXTENSION_RENDER_DEFAULTS = {
    "generate_rules_license_metadata": True,
}

def _render_defaults():
    """The render settings of an extension hub before any `render_config` tag.

    Returns:
        dict: `render_config()`'s values with `_EXTENSION_RENDER_DEFAULTS` applied.
    """
    return json.decode(generate_render_config()) | _EXTENSION_RENDER_DEFAULTS

def _collect_build_wide_render_config(module_ctx):
    """The build-wide render settings, from the root module's global `render_config`.

    Args:
        module_ctx (module_ctx): The module extension's context.

    Returns:
        dict: The values of `_BUILD_WIDE_RENDER_SETTINGS`, defaults when the root sets none.
    """
    defaults = _render_defaults()
    settings = {name: defaults[name] for name in _BUILD_WIDE_RENDER_SETTINGS}

    global_tags = []
    for mod in module_ctx.modules:
        for tag in mod.tags.render_config:
            if not _is_global(tag):
                continue
            if not mod.is_root:
                fail("`render_config(repositories = [\"*\"])` may only be used by the root module, not by `{}`.".format(mod.name))
            global_tags.append(tag)
    if len(global_tags) > 1:
        fail("Only one `render_config(repositories = [\"*\"])` is allowed.")
    for tag in global_tags:
        settings.update({name: getattr(tag, name) for name in _BUILD_WIDE_RENDER_SETTINGS})
    settings["platforms_template"] = _canonical_platforms_template(settings["platforms_template"])
    return settings

def _collect_render_config(module, repository, build_wide):
    """Collect the render_config for the given crate_universe module.

    Args:
        module (StarlarkBazelModule): The current `crate` module.
        repository (str): The name of the repository to collect the config for.
        build_wide (dict): The build-wide settings, see `_collect_build_wide_render_config`.

    Returns:
        dict: The rendering config to use.
    """

    defaults = _render_defaults()
    config = None
    for raw_config in module.tags.render_config:
        # Global configs carry the build-wide settings and nothing else.
        if _is_global(raw_config):
            continue

        # if the repositories is empty we apply the config to all repositories
        # otherwise we filter for the requested repositories
        if raw_config.repositories and repository not in raw_config.repositories:
            continue

        # The build-wide settings are the root's to make, for every hub at once.
        for name in _BUILD_WIDE_RENDER_SETTINGS:
            if getattr(raw_config, name) != defaults[name]:
                if module.is_root:
                    fail(("`render_config.{}` applies to the whole build. Set it on a " +
                          "`render_config(repositories = [\"*\"])` in `{}`.").format(name, module.name))

                # buildifier: disable=print
                print(("WARN: `render_config.{}` set by module `{}` is ignored; the root module " +
                       "decides it for the whole build.").format(name, module.name))

        if config:
            fail("Multiple render configs provided for module `{}`. Only 1 is allowed.".format(
                module.name,
            ))

        config_kwargs = {attr: getattr(raw_config, attr) for attr in dir(raw_config)}

        if "repositories" in config_kwargs:
            config_kwargs.pop("repositories")

        if "default_alias_rule_bzl" in config_kwargs:
            default_alias_rule_bzl = config_kwargs.pop("default_alias_rule_bzl")
            if default_alias_rule_bzl:
                config_kwargs["default_alias_rule"] = str(default_alias_rule_bzl)

        if "default_alias_rule_name" in config_kwargs:
            config_kwargs["default_alias_rule"] = "{}:{}".format(
                config_kwargs.get("default_alias_rule", ""),
                config_kwargs.pop("default_alias_rule_name"),
            ).lstrip(":")

        # bzlmod doesn't allow passing `None` as a default parameter to indicate a value was
        # not provided. So for backward compatibility, certain empty values are assumed to be
        # not provided and thus are converted explicitly to `None`.
        for null_defaults in ["vendor_mode", "regen_command", "default_package_name"]:
            if config_kwargs[null_defaults] == "":
                config_kwargs[null_defaults] = None

        config = json.decode(generate_render_config(**config_kwargs))

    if not config:
        config = defaults

    if not config["regen_command"]:
        config["regen_command"] = "bazel mod show_repo '{}'".format(module.name)

    config.update(build_wide)

    return config

def _collect_splicing_config(module, repository):
    """Collect the splicing_config for the given crate_universe module.

    Args:
        module (StarlarkBazelModule): The current `crate` module.
        repository (str): The name of the repository to collect the config for.

    Returns:
        dict: The splicing config to use.
    """
    config = None
    for raw_config in module.tags.splicing_config:
        # if the repositories is empty we apply the config to all repositories
        # otherwise we filter for the requested repositories
        if raw_config.repositories and repository not in raw_config.repositories:
            continue

        if config:
            fail("Multiple render configs provided for module `{}`. Only 1 is allowed.".format(
                module.name,
            ))

        config_kwargs = {attr: getattr(raw_config, attr) for attr in dir(raw_config)}

        if "repositories" in config_kwargs:
            config_kwargs.pop("repositories")

        config = json.decode(generate_splicing_config(**config_kwargs))

    if not config:
        config = json.decode(generate_splicing_config())

    return config

def _resolve_hub(
        *,
        module_ctx,
        cargo_bazel_fn,
        new_resolving_cargo_bazel_fn,
        cfg,
        annotations,
        render_config,
        splicing_config,
        lockfile,
        lockfile_mode,
        skip_cargo_lockfile_overwrite,
        strip_internal_dependencies_from_cargo_lockfile,
        is_root,
        cargo_lockfile = None,
        manifests = {},
        packages = {}):
    """Resolves one hub: splices, repins or reuses its lockfile, and returns where to find it.

    Rendering happens afterwards for every hub at once, see `_generate_pool`.

    Args:
        module_ctx (module_ctx): The module context object.
        cargo_bazel_fn (callable): A callback for invoking the `cargo-bazel` binary.
        new_resolving_cargo_bazel_fn (callable): A callback producing a `cargo_bazel_fn` which also
            has the host Rust toolchain. Only called when a resolution is needed.
        cfg (object): The module tag from `from_cargo` or `from_specs`
        annotations (dict): The set of annotation tag classes that apply to this closure, keyed by crate name.
        render_config (dict): The render config to use.
        splicing_config (dict): The splicing config to use.
        lockfile (path): The path to the crate_universe lock file, if one was provided.
        lockfile_mode (str): What to do when the lockfile is out of date, one of `LOCKFILE_MODES`.
        skip_cargo_lockfile_overwrite (bool): Whether to skip writing the cargo lockfile back after resolving.
            You may want to set this if your dependency versions are maintained externally through a non-trivial set-up.
            But you probably don't want to set this.
        strip_internal_dependencies_from_cargo_lockfile (bool): Whether to strip internal dependencies from the cargo lockfile.
            You may want to use this if you want to maintain a cargo lockfile for bazel only.
            Bazel only requires external dependencies to be present in the lockfile.
            By removing internal dependencies, the lockfile changes less frequently which reduces merge conflicts
            in other lockfiles where the cargo lockfile's sha is stored.
        is_root (bool): Whether the module owning this extension call is the workspace's root module.
            A dependency module's lockfile is used as shipped: the digest check is skipped and it is
            never repinned. A dependency module without one is resolved here and the resolution kept
            in the extension's facts.
        cargo_lockfile (path): Path to Cargo.lock, if we have one.
        manifests (dict): The set of Cargo.toml manifests that apply to this closure, if any, keyed by path.
        packages (dict): The set of extra cargo crate tags that apply to this closure, if any, keyed by package name.
    """

    tag_path = module_ctx.path(cfg.name)

    config_file = tag_path.get_child("config.json")
    module_ctx.file(
        config_file,
        executable = False,
        content = generate_config_file(
            module_ctx,
            mode = "remote",
            annotations = annotations,
            generate_build_scripts = cfg.generate_build_scripts,
            supported_platform_triples = cfg.supported_platform_triples,
            repository_name = cfg.name,
            output_pkg = cfg.name,
            workspace_name = cfg.name,
            generate_binaries = cfg.generate_binaries,
            render_config = render_config,
            repository_ctx = module_ctx,
        ),
    )

    splicing_manifest = tag_path.get_child("splicing_manifest.json")
    module_ctx.file(
        splicing_manifest,
        executable = False,
        content = generate_splicing_manifest(
            packages = packages,
            splicing_config = splicing_config,
            cargo_config = cfg.cargo_config,
            manifests = manifests,
            manifest_to_path = module_ctx.path,
            cargo_lockfile = cargo_lockfile,
        ),
    )

    # The workspace root when one is explicitly provided.
    # buildifier: disable=canonical-repository
    nonhermetic_root_bazel_workspace_dir = module_ctx.path(Label("@@//:MODULE.bazel")).dirname

    # Files of other repositories are never modified. A `Cargo.lock` from one
    # is used as-is and the resolution must hold to it exactly; a lockfile
    # from one cannot be repinned, so an out of date one is an error.
    # https://github.com/bazelbuild/rules_rust/issues/1738
    if cargo_lockfile and not is_within_workspace(cargo_lockfile, nonhermetic_root_bazel_workspace_dir):
        skip_cargo_lockfile_overwrite = True
    lockfile_is_writable = lockfile == None or is_within_workspace(lockfile, nonhermetic_root_bazel_workspace_dir)

    # Whether the resolution should be recorded in the extension's facts.
    record_fact = False

    # Determine whether or not to repin dependencies. A lockfile shipped by a
    # dependency module is honored as it is: its digest is not checked, since it
    # can legitimately differ across rules_rust versions between the producing
    # module and the consumer, and it cannot be repinned, since it lives in a
    # read-only bzlmod cache. A dependency module without one is resolved here,
    # as Cargo would from its manifests and `Cargo.lock`, and the resolution is
    # kept in this module's facts like a root repository without a lockfile.
    if not is_root and lockfile:
        # The lockfile may come from an older or newer rules_rust than this one.
        # One this version cannot read is a hint rather than an input: the
        # repository is resolved as if the module had shipped none.
        shipped = lockfile_is_readable(
            cargo_bazel_fn = cargo_bazel_fn,
            lockfile_path = lockfile,
            config = config_file,
            splicing_manifest = splicing_manifest,
        )
        if not shipped.readable:
            # buildifier: disable=print
            print(("The lockfile shipped by a dependency module for the crate_universe repository " +
                   "`{}` could not be understood by this version of rules_rust, so the repository's " +
                   "crates were resolved from the module's manifests instead:\n{}").format(cfg.name, shipped.error))
            lockfile = None
    if not is_root and lockfile:
        repin = False
    elif not lockfile and hasattr(module_ctx, "facts"):
        # Without a `lockfile`, the last resolution is kept in the extension's
        # facts, which Bazel persists in `MODULE.bazel.lock`, so it is only
        # redone when its inputs change.
        lockfile = tag_path.get_child("cargo-bazel-lock.json")
        cached = module_ctx.facts.get(cfg.name)
        module_ctx.file(lockfile, cached or "")
        record_fact = True
        repin = not cached or determine_repin(
            repository_ctx = module_ctx,
            repository_name = cfg.name,
            cargo_bazel_fn = cargo_bazel_fn,
            lockfile_path = lockfile,
            config = config_file,
            splicing_manifest = splicing_manifest,
            lockfile_mode = "update",
        )
    else:
        repin = not lockfile or determine_repin(
            repository_ctx = module_ctx,
            repository_name = cfg.name,
            cargo_bazel_fn = cargo_bazel_fn,
            lockfile_path = lockfile,
            config = config_file,
            splicing_manifest = splicing_manifest,
            lockfile_mode = lockfile_mode,
            allow_repin = lockfile_is_writable,
        )

    # If re-pinning is enabled, gather additional inputs for the generator
    kwargs = dict()
    if repin:
        if not is_root and cargo_lockfile == None:
            # buildifier: disable=print
            print(("The crate_universe repository `{}` is declared by a dependency module with " +
                   "neither a `lockfile` nor a `cargo_lockfile`, so its crates resolve to the newest " +
                   "versions satisfying its requirements; other consumers of the module may resolve " +
                   "different versions. The module should ship a `Cargo.lock`.").format(cfg.name))
        module_ctx.report_progress("Splicing Cargo workspace for `{}`".format(cfg.name))

        # Generate a top level Cargo workspace and manifest for use in generation
        splice_outputs = splice_workspace_manifest(
            repository_ctx = module_ctx,
            cargo_bazel_fn = new_resolving_cargo_bazel_fn(),
            cargo_lockfile = cargo_lockfile,
            splicing_manifest = splicing_manifest,
            config_path = config_file,
            output_dir = tag_path.get_child("splicing-output"),
            debug_workspace_dir = tag_path.get_child("splicing-workspace"),
            skip_cargo_lockfile_overwrite = skip_cargo_lockfile_overwrite,
            nonhermetic_root_bazel_workspace_dir = nonhermetic_root_bazel_workspace_dir,
            repository_name = cfg.name,
        )

        # If a cargo lockfile was not provided, use the splicing lockfile.
        if cargo_lockfile == None:
            cargo_lockfile = splice_outputs.cargo_lock

        # Create a fallback lockfile to be parsed downstream.
        if lockfile == None:
            lockfile = tag_path.get_child("cargo-bazel-lock.json")
            module_ctx.file(lockfile, "")

        kwargs.update({
            "metadata": splice_outputs.metadata,
        })

        for path_to_track in splice_outputs.extra_paths_to_track:
            # We can only watch paths in our workspace.
            if path_to_track.startswith(str(nonhermetic_root_bazel_workspace_dir)):
                module_ctx.watch(path_to_track)

    paths_to_track_file = tag_path.get_child("paths_to_track.json")
    warnings_output_file = tag_path.get_child("warnings_output.json")
    hub_packages_output_file = tag_path.get_child("hub_packages.json")

    # Run the generator
    module_ctx.report_progress("Generating crate BUILD files for `{}`".format(cfg.name))
    execute_generator(
        cargo_bazel_fn = cargo_bazel_fn,
        config = config_file,
        splicing_manifest = splicing_manifest,
        lockfile_path = lockfile,
        cargo_lockfile_path = cargo_lockfile,
        repository_dir = tag_path,
        nonhermetic_root_bazel_workspace_dir = nonhermetic_root_bazel_workspace_dir,
        paths_to_track_file = paths_to_track_file,
        warnings_output_file = warnings_output_file,
        hub_packages_output_file = hub_packages_output_file,
        skip_cargo_lockfile_overwrite = skip_cargo_lockfile_overwrite,
        strip_internal_dependencies_from_cargo_lockfile = strip_internal_dependencies_from_cargo_lockfile,
        skip_render = True,
        **kwargs
    )

    paths_to_track = json.decode(module_ctx.read(paths_to_track_file))
    for path in paths_to_track:
        module_ctx.watch(path)

    warnings_output_file = json.decode(module_ctx.read(warnings_output_file))
    for warning in warnings_output_file:
        # buildifier: disable=print
        print("WARN: {}".format(warning))

    return struct(
        fact = module_ctx.read(lockfile) if record_fact else None,
        lockfile = lockfile,
        config = config_file,
    )

def _generate_pool(module_ctx, cargo_bazel_fn, hubs):
    """Renders the shared crate repositories and every hub's alias layer.

    Crates with equal closures - the same resolved context, dependencies and
    render settings - share one repository whichever hubs they came from, see
    `cargo-bazel pool`. Hubs hold only aliases into those repositories.

    Args:
        module_ctx (module_ctx): The module context object.
        cargo_bazel_fn (callable): A callback for invoking the `cargo-bazel` binary.
        hubs (list): `struct(name, lockfile, config)` for every resolved hub.
    """
    pool_dir = module_ctx.path("pool")
    hubs_file = pool_dir.get_child("hubs.json")
    module_ctx.file(hubs_file, json.encode([
        {"config": str(hub.config), "lockfile": str(hub.lockfile), "name": hub.name}
        for hub in hubs
    ]))

    module_ctx.report_progress("Pooling crates across {} repositories".format(len(hubs)))
    cargo_bazel_fn(args = ["pool", "--hubs", hubs_file, "--output-dir", pool_dir])

    manifest = json.decode(module_ctx.read(pool_dir.get_child("pool.json")))

    for repo_name, repo in manifest["repositories"].items():
        build_file_content = module_ctx.read(pool_dir.get_child(repo["build_file"]))
        source = repo["repository"]
        if "Http" in source:
            # Replicates functionality in repo_http.j2.
            source = source["Http"]
            http_archive(
                name = repo_name,
                patch_args = source.get("patch_args", None),
                patch_tool = source.get("patch_tool", None),
                patches = source.get("patches", None),
                remote_patch_strip = 1,
                sha256 = source.get("sha256", None),
                type = "tar.gz",
                urls = [source["url"]],
                strip_prefix = "%s-%s" % (repo["name"], repo["version"]),
                build_file_content = build_file_content,
            )
        elif "Git" in source:
            # Replicates functionality in repo_git.j2
            source = source["Git"]
            kwargs = {}
            for k, v in source["commitish"].items():
                if k == "Rev":
                    kwargs["commit"] = v
                else:
                    kwargs[k.lower()] = v
            git_repository(
                name = repo_name,
                init_submodules = True,
                patch_args = source.get("patch_args", None),
                patch_tool = source.get("patch_tool", None),
                patches = source.get("patches", None),
                shallow_since = source.get("shallow_since", None),
                remote = source["remote"],
                build_file_content = build_file_content,
                strip_prefix = source.get("strip_prefix", None),
                **kwargs
            )
        elif "Path" in source:
            kwargs = {}
            if len(CARGO_BAZEL_URLS) == 0:
                kwargs["generator"] = "@cargo_bazel_bootstrap//:cargo-bazel"
            local_crate_mirror(
                name = repo_name,
                build_file_content = build_file_content,
                path = source["Path"]["path"],
                **kwargs
            )
        else:
            fail("Invalid repo: expected Http, Git or Path to exist for crate %s-%s, got %s" % (repo["name"], repo["version"], source))

    for hub_name, hub in manifest["hubs"].items():
        hub_dir = pool_dir.get_child("hubs").get_child(hub_name)
        crates_vendor_remote_repository(
            name = hub_name,
            contents = {
                path: module_ctx.read(hub_dir.get_child(path))
                for path in hub["files"]
            },
        )

def _package_to_json(p):
    # Avoid adding unspecified properties.
    # If we add them as empty strings, cargo-bazel will be unhappy.
    return json.encode({
        k: v
        for k, v in structs.to_dict(p).items()
        if v or k == "default_features"
    })

def _get_generator(module_ctx, host_triple):
    """Query Network Resources to local a `cargo-bazel` binary.

    Based off get_generator in crates_universe/private/generate_utils.bzl

    Args:
        module_ctx (module_ctx): The rules context object
        host_triple (struct): A triple struct that represents the host.

    Returns:
        tuple(path, dict) The path to a 'cargo-bazel' binary. The pairing (dict)
            may be `None` if there is not need to update the attribute
    """
    use_environ = False
    for var in GENERATOR_ENV_VARS:
        if var in module_ctx.os.environ:
            use_environ = True

    if use_environ:
        generator_sha256 = module_ctx.os.environ.get(CARGO_BAZEL_GENERATOR_SHA256)
        generator_url = module_ctx.os.environ.get(CARGO_BAZEL_GENERATOR_URL)
    elif len(CARGO_BAZEL_URLS) == 0:
        # For Bazel 7 and below, `module_ctx.path` will also watch files so to avoid
        # volatility in lock files caused by referencing host specific files, direct
        # references are avoided.
        return module_ctx.path(Label("@cargo_bazel_bootstrap//:BUILD.bazel")).dirname.get_child("cargo-bazel")

    else:
        generator_sha256 = CARGO_BAZEL_SHA256S.get(host_triple.str)
        generator_url = CARGO_BAZEL_URLS.get(host_triple.str)

    if not generator_url:
        fail((
            "No generator URL was found either in the `CARGO_BAZEL_GENERATOR_URL` " +
            "environment variable or for the `{}` triple in the `generator_urls` attribute"
        ).format(host_triple.str))

    output = module_ctx.path("cargo-bazel.exe" if "win" in module_ctx.os.name else "cargo-bazel")

    # Download the file into place
    download_kwargs = {
        "executable": True,
        "output": output,
        "url": generator_url,
    }

    if generator_sha256:
        download_kwargs.update({"sha256": generator_sha256})

    module_ctx.download(**download_kwargs)
    return output

def _collect_host_tools(module_ctx):
    """The Cargo the root module resolves every hub with, if it named one.

    Args:
        module_ctx (module_ctx): The module extension's context.

    Returns:
        struct: `cargo` and `rustc` labels (`rustc` may be `None`), or `None` when
            the downloaded Cargo is to be used.
    """
    tags = []
    for mod in module_ctx.modules:
        for tag in mod.tags.host_tools:
            if not mod.is_root:
                fail(("`crate.host_tools` may only be used by the root module, not by `{}`: resolving " +
                      "runs on the machine running Bazel, whose Cargo is the root module's to choose.").format(mod.name))
            tags.append(tag)
    if len(tags) > 1:
        fail("Only one `crate.host_tools` is allowed.")
    for tag in tags:
        return struct(cargo = tag.cargo, rustc = tag.rustc)
    return None

def _check_cargo_runs(module_ctx, cargo_path):
    """Fails with an explanation when `cargo_path` cannot be executed on this host.

    A Cargo downloaded from the Rust distribution needs the host's dynamic
    loader at its conventional path, which a NixOS host lacks unless `nix-ld`
    provides it. Without this check that surfaces as a loader error from deep
    inside `cargo metadata`.

    Args:
        module_ctx (module_ctx): The module extension's context.
        cargo_path (path): The Cargo about to resolve crates.
    """
    result = module_ctx.execute([cargo_path, "-vV"], timeout = 120)
    if result.return_code != 0:
        fail(("The Cargo at `{}` does not run on this host (exit code {}):\n{}\n" +
              "Resolving crates runs Cargo on the machine running Bazel. A Cargo from the Rust " +
              "distribution needs the host's dynamic loader, which NixOS has only with nix-ld. Give the " +
              "`crate` extension a Cargo built for this host instead, in the root module: " +
              "`crate.host_tools(cargo = \"@<repository>//:bin/cargo\")`, for example a repository " +
              "created by rules_nixpkgs.").format(cargo_path, result.return_code, result.stderr.strip()))

def _get_host_cargo_rustc(module_ctx, host_triple, host_tools_repo, host_tools):
    """A helper function to get the path to the host cargo, and rustc when there is one.

    Fetches the repository the Cargo comes from, so only call this when a
    resolution is needed, and checks that the Cargo runs.

    Args:
        module_ctx (module_ctx): The module extension's context.
        host_triple (triple): The platform triple for the machine executing this extension.
        host_tools_repo (Label): A repository providing `bin/cargo` and `bin/rustc` (a hub's
            `host_tools`), or `None`.
        host_tools (struct): The root module's `crate.host_tools`, or `None`.
    Returns:
        tuple[Path, Path]: The path to cargo and the path to rustc, `None` without one.
    """
    binary_ext = system_to_binary_ext(host_triple.system)

    if host_tools_repo:
        root = module_ctx.path(host_tools_repo).dirname
        cargo_path = root.get_child("bin/cargo{}".format(binary_ext))
        rustc_path = root.get_child("bin/rustc{}".format(binary_ext))
    elif host_tools:
        cargo_path = module_ctx.path(host_tools.cargo)
        rustc_path = module_ctx.path(host_tools.rustc) if host_tools.rustc else None
    else:
        # Resolving needs Cargo and nothing else of a toolchain: cargo-bazel
        # stands in for rustc. The `rust` extension fetches that Cargo alone
        # for every host platform. `host_triple` names the musl build of the
        # generator on Linux; Cargo is fetched for the platform's own triple.
        cargo_triple = get_host_triple(module_ctx).str
        if cargo_triple not in DEFAULT_TOOLCHAIN_TRIPLES:
            fail(
                ("rules_rust registers no Cargo for the host platform `{}`. Name one with " +
                 "`crate.host_tools(cargo = ...)` in the root module.").format(cargo_triple),
            )
        repo = cargo_tools_repository_name(cargo_triple)
        root = module_ctx.path(Label("@{}//:BUILD.bazel".format(repo))).dirname
        cargo_path = root.get_child("bin/cargo{}".format(binary_ext))
        rustc_path = None

    _check_cargo_runs(module_ctx, cargo_path)
    return cargo_path, rustc_path

def _new_resolving_cargo_bazel_fn(module_ctx, generator, host_triple, cfg, is_root, host_tools):
    """A callback producing a `cargo_bazel_fn` with the host `cargo` for `cfg`.

    The Cargo repository is fetched when the callback runs, so hubs whose
    lockfile is up to date never fetch it.

    Args:
        module_ctx (module_ctx): The module extension's context.
        generator (path): The path to the `cargo-bazel` binary.
        host_triple (triple): The platform triple for the machine executing this extension.
        cfg (object): The module tag from `from_cargo` or `from_specs`.
        is_root (bool): Whether the root module declared `cfg`.
        host_tools (struct): The root module's `crate.host_tools`, or `None`.
    Returns:
        callable: A zero-argument function returning a `cargo_bazel_fn`.
    """

    # Which Cargo runs is the root module's choice: it is the root's machine.
    host_tools_repo = cfg.host_tools
    if host_tools_repo and not is_root:
        # buildifier: disable=print
        print(("WARN: `host_tools` of hub `{}` is ignored; the root module decides the Cargo " +
               "that resolves, with `crate.host_tools`.").format(cfg.name))
        host_tools_repo = None

    def _new():
        cargo_path, rustc_path = _get_host_cargo_rustc(module_ctx, host_triple, host_tools_repo, host_tools)
        return new_cargo_bazel_fn(
            repository_ctx = module_ctx,
            cargo_bazel_path = generator,
            cargo_path = cargo_path,
            rustc_path = rustc_path,
            isolated = cfg.isolated,
        )

    return _new

def _update_annotations(store, crate, version, triples, annotation_select_dict):
    """Insert build-script data/env for each target triple if keys exist."""
    crate_info = store.get(crate)
    if crate_info == None:
        _insert_annotation(store, crate, version, {})
        crate_info = store.get(crate)

    version_info = crate_info.get(version)
    if version_info == None:
        _insert_annotation(store, crate, version, {})
        version_info = crate_info.get(version)

    filtered_annotation_select_dict = _filter_dict(annotation_select_dict)

    # `labels` name targets for the strings of every triple rather than
    # being selected on, so they merge into the annotation as a whole.
    version_info.setdefault("labels", {}).update(
        filtered_annotation_select_dict.pop("labels", {}),
    )

    for triple in triples:
        for field, value in filtered_annotation_select_dict.items():
            _insert_select(
                crate,
                version,
                triple,
                version_info,
                field,
                value,
            )

def _annotation_tag_to_dict(annotation_tag):
    """Converts an `annotation` tag into the keyword arguments of `crate.annotation`.

    Args:
        annotation_tag (struct): The tag.

    Returns:
        tuple: The crate name, version, `repositories` and the annotation dict.
    """
    annotation_dict = _resolve_label_attrs(structs.to_dict(annotation_tag))

    repositories = annotation_dict.pop("repositories")
    crate = annotation_dict.pop("crate")
    version = annotation_dict.pop("version")

    # The crate.annotation function can take in either a list or a bool.
    # For the tag-based method, because it has type safety, we have to
    # split it into two parameters.
    if annotation_dict.pop("gen_all_binaries"):
        annotation_dict["gen_binaries"] = True
    annotation_dict["gen_build_script"] = _OPT_BOOL_VALUES[annotation_dict["gen_build_script"]]

    # Convert the tri-state string values ("auto"/"on"/"off") into the
    # `int` representation understood by `crate.annotation` (`None`, `1`,
    # or `0` respectively).
    for opt_bool_key in (
        "build_script_use_cc_toolchain",
        "build_script_use_default_shell_env",
    ):
        bool_value = _OPT_BOOL_VALUES[annotation_dict[opt_bool_key]]
        if bool_value == None:
            annotation_dict.pop(opt_bool_key)
        else:
            annotation_dict[opt_bool_key] = int(bool_value)

    # Process the override targets for the annotation.
    # In the non-bzlmod approach, this is given as a dict
    # with the possible keys "`proc-macro`, `custom-build`, `lib`, `bin`".
    # With the tag-based approach used in Bzlmod, we run into an issue
    # where there is no dict type that takes a string as a key and a Label as the value.
    # To work around this, we split the override option into four, and reconstruct the
    # dictionary here during processing
    annotation_dict["override_targets"] = dict()
    replacement = annotation_dict.pop("override_target_lib")
    if replacement:
        annotation_dict["override_targets"]["lib"] = str(replacement)

    replacement = annotation_dict.pop("override_target_proc_macro")
    if replacement:
        annotation_dict["override_targets"]["proc-macro"] = str(replacement)

    replacement = annotation_dict.pop("override_target_build_script")
    if replacement:
        annotation_dict["override_targets"]["custom-build"] = str(replacement)

    replacement = annotation_dict.pop("override_target_bin")
    if replacement:
        annotation_dict["override_targets"]["bin"] = str(replacement)

    return crate, version, repositories, annotation_dict

def _scope_of(mod, repositories):
    """Classifies the `repositories` of an annotation tag.

    Args:
        mod (bazel_module): The module which declared the tag.
        repositories (list): The tag's `repositories` attribute.

    Returns:
        str: `"global"` for `["*"]`, `"module"` when empty and `"repositories"` otherwise.
    """
    if repositories == ["*"]:
        if not mod.is_root:
            fail(
                "`repositories = [\"*\"]` applies an annotation to every crate repository " +
                "of every module and so may only be used by the root module, not `{}`.".format(mod.name),
            )
        return "global"
    if not repositories:
        return "module"
    return "repositories"

def _resolve_label_attrs(annotation_dict):
    """Stringify the label typed attributes of an annotation tag.

    Labels become their canonical form, which is valid from any repository, and
    each `<name>_str` list is folded into `<name>`.

    Args:
        annotation_dict (dict): The attributes of an `annotation` or `annotation_select` tag.

    Returns:
        dict: The same dict with only string valued label attributes.
    """
    for name in _LABEL_LIST_ATTRS:
        annotation_dict[name] = [str(label) for label in annotation_dict[name]] + annotation_dict.pop(name + "_str")
    annotation_dict["labels"] = {str(label): name for label, name in annotation_dict["labels"].items()}
    return annotation_dict

def _insert_annotation(store, crate, version, annotation):
    """Insert `annotation` (dict) into `store[crate][version]`.

    Raises `fail()` if that (crate, version) pair already exists.
    """
    crate_map = store.setdefault(crate, {})  # create nested map if needed

    if version in crate_map:
        fail("Duplicate annotation for crate {} version {}".format(crate, version))

    crate_map[version] = annotation

def _insert_select(crate, version, triple, annotation, field, value):
    """
    Add a per-triple override to annotation[field].

    If annotation[field] is in a list or dict, we wrap that into the common field. Then

    On later calls we just update the existing selects.
    """
    current = annotation.get(field)

    if type(current) == "struct":
        if triple in current.selects:
            fail("Duplicate annotation for crate {} version {} triple {}".format(crate, version, triple))

        current.selects.update({triple: value})
        return

    # `common` cannot be None
    if current == None:
        if type(value) == type(""):
            current = ""
        elif type(value) == type([]):
            current = []
        elif type(value) == type({}):
            current = {}

    annotation[field] = struct(
        common = current,
        selects = {triple: value},
    )

def _create_annotation(version, annotation_dict):
    return _crate_universe_crate.annotation(
        version = version,
        **_filter_dict(annotation_dict)
    )

def _collapse_crate_versions(crates, create = _create_annotation):
    """{crate: {version: annotation}} -> {crate: [annotation,…]}"""
    return {
        crate: [create(version, annotation) for version, annotation in versions.items()]
        for crate, versions in crates.items()
    }

def _collapse_versions(repo_specific, module, create = _create_annotation):
    """
    Return new (repo_specific, module) dicts with versions collapsed.

    repo_specific: {repo: {crate: {version: annotation}}}
    module       : {crate: {version: annotation}}
    """
    new_repo_specific = {
        repo: _collapse_crate_versions(crates, create)
        for repo, crates in repo_specific.items()
    }
    new_module = _collapse_crate_versions(module, create)
    return new_repo_specific, new_module

def _filter_dict(dict):
    return {
        k: v
        for k, v in dict.items()
        # Tag classes can't take in None, but the function requires None
        # instead of the empty values in many cases.
        # https://github.com/bazelbuild/bazel/issues/20744
        if v != "" and v != [] and v != {}
    }

def _crate_impl(module_ctx):
    reproducible = True
    host_triple = get_host_triple(module_ctx, abi = {
        "aarch64-unknown-linux": "musl",
        "x86_64-unknown-linux": "musl",
    })
    generator = _get_generator(module_ctx, host_triple)

    all_repos = []

    # Annotations the root module applies to every crate repository of every
    # module (`repositories = ["*"]`). The root module is always first in
    # `module_ctx.modules`, so these are complete before any other module's
    # repositories are generated.
    global_annotations = {}

    # The resolutions of root repositories without a `lockfile`, keyed by name.
    # Returned as facts so Bazel persists them in `MODULE.bazel.lock`.
    facts = {}

    # Render settings the root module makes for every hub.
    build_wide_render_config = _collect_build_wide_render_config(module_ctx)

    # The Cargo the root module resolves with, if not the downloaded one.
    host_tools = _collect_host_tools(module_ctx)

    # Every resolved hub, rendered together once all are known.
    hubs = []
    pool_cargo_bazel_fn = None

    for mod in module_ctx.modules:
        if not mod.tags.from_cargo and not mod.tags.from_specs:
            fail("`.from_cargo` or `.from_specs` are required. Please update {}".format(mod.name))

        local_repos = []
        module_annotations = {}
        repo_specific_annotations = {}
        for annotation_tag in mod.tags.annotation:
            crate, version, repositories, annotation_dict = _annotation_tag_to_dict(annotation_tag)
            scope = _scope_of(mod, repositories)
            if scope == "global":
                _insert_annotation(global_annotations, crate, version, annotation_dict)
            elif scope == "module":
                _insert_annotation(module_annotations, crate, version, annotation_dict)
            else:
                for repo in repositories:
                    # each repo gets its own top-level dict:
                    repo_map = repo_specific_annotations.setdefault(repo, {})
                    _insert_annotation(repo_map, crate, version, annotation_dict)

        for annotation_select_tag in mod.tags.annotation_select:
            annotation_select_dict = _resolve_label_attrs(structs.to_dict(annotation_select_tag))
            repositories = annotation_select_dict.pop("repositories")
            crate = annotation_select_dict.pop("crate")
            triples = annotation_select_dict.pop("triples")
            version = annotation_select_dict.pop("version")

            scope = _scope_of(mod, repositories)
            if scope == "global":
                _update_annotations(global_annotations, crate, version, triples, annotation_select_dict)
            elif scope == "module":
                _update_annotations(module_annotations, crate, version, triples, annotation_select_dict)
            else:
                for repo in repositories:
                    _update_annotations(
                        repo_specific_annotations.setdefault(repo, {}),
                        crate,
                        version,
                        triples,
                        annotation_select_dict,
                    )

        # Now transform the annotations into a format that the `_resolve_hub` function expects.
        repo_specific_annotations, module_annotations = _collapse_versions(repo_specific_annotations, module_annotations)
        collapsed_global_annotations = _collapse_crate_versions(global_annotations)
        common_specs = []
        repo_specific_specs = {}
        for spec in mod.tags.spec:
            if not spec.repositories:
                common_specs.append(spec)
            else:
                for name in spec.repositories:
                    if name not in repo_specific_specs:
                        repo_specific_specs[name] = []
                    repo_specific_specs[name].append(spec)

        # Do a quick sanity check to ensure no annotations or specs are referring to
        # non-existent modules.
        for cfg in mod.tags.from_cargo + mod.tags.from_specs:
            if cfg.name in local_repos:
                fail("Defined two crate universes with the same name in the same MODULE.bazel file (`{}`). Use the `name` tag to give them different names.".format(
                    cfg.name,
                ))
            if cfg.name in all_repos:
                fail("Defined two crate universes with the same name in different MODULE.bazel files (`{}`). Either give one a different name, or use `use_extension(isolate=True)`".format(
                    cfg.name,
                ))
            all_repos.append(cfg.name)
            local_repos.append(cfg.name)

        for repo in repo_specific_annotations:
            if repo not in local_repos:
                fail("Annotation specified for repo {}, but the module defined repositories {}".format(repo, local_repos))

        for repo in repo_specific_specs:
            if repo not in local_repos:
                fail("Spec specified for repo {}, but the module defined repositories {}".format(repo, local_repos))

        for cfg in mod.tags.from_cargo + mod.tags.from_specs:
            # Watch inputs not modified by the generator. Calling `module_ctx.watch` will cause restarts of
            # the implementation function of the module extension when the file has changed.
            if cfg.cargo_lockfile:
                module_ctx.watch(cfg.cargo_lockfile)
            if cfg.cargo_config:
                module_ctx.watch(cfg.cargo_config)
            if hasattr(cfg, "manifests"):
                for m in cfg.manifests:
                    module_ctx.watch(m)
            cargo_bazel_fn = new_cargo_bazel_fn(
                repository_ctx = module_ctx,
                cargo_bazel_path = generator,
                isolated = cfg.isolated,
            )

            rendering_config = _collect_render_config(mod, cfg.name, build_wide_render_config)
            splicing_config = _collect_splicing_config(mod, cfg.name)

            annotations = _annotations_for_repo(
                collapsed_global_annotations,
                module_annotations,
                repo_specific_annotations.get(cfg.name),
            )

            lockfile_path = None
            if cfg.lockfile:
                lockfile_path = module_ctx.path(cfg.lockfile)
            elif not hasattr(module_ctx, "facts"):
                reproducible = False

            cargo_lockfile = None
            if cfg.cargo_lockfile:
                cargo_lockfile = module_ctx.path(cfg.cargo_lockfile)
            else:
                reproducible = False

            manifests = {}
            packages = {}

            # Only `from_cargo` instances will have `manifests`.
            if hasattr(cfg, "manifests"):
                manifests = {str(module_ctx.path(m)): str(m) for m in cfg.manifests}

            packages = {
                p.package_alias or p.package: _package_to_json(p)
                for p in common_specs + repo_specific_specs.get(cfg.name, [])
            }

            generated = _resolve_hub(
                module_ctx = module_ctx,
                cargo_bazel_fn = cargo_bazel_fn,
                new_resolving_cargo_bazel_fn = _new_resolving_cargo_bazel_fn(module_ctx, generator, host_triple, cfg, mod.is_root, host_tools),
                cfg = cfg,
                annotations = annotations,
                lockfile = lockfile_path,
                lockfile_mode = cfg.lockfile_mode,
                cargo_lockfile = cargo_lockfile,
                render_config = rendering_config,
                splicing_config = splicing_config,
                manifests = manifests,
                packages = packages,
                skip_cargo_lockfile_overwrite = cfg.skip_cargo_lockfile_overwrite,
                strip_internal_dependencies_from_cargo_lockfile = cfg.strip_internal_dependencies_from_cargo_lockfile,
                is_root = mod.is_root,
            )
            if generated.fact != None:
                facts[cfg.name] = generated.fact
            hubs.append(struct(name = cfg.name, lockfile = generated.lockfile, config = generated.config))
            pool_cargo_bazel_fn = cargo_bazel_fn

            # Watch cfg.lockfile AFTER generation. The generator may modify it during
            # repin, and in Bazel 9 module_ctx.read verifies digests for files already
            # read, which would crash if the lockfile changed between watch and read.
            if cfg.lockfile:
                module_ctx.watch(cfg.lockfile)

    if hubs:
        _generate_pool(module_ctx, pool_cargo_bazel_fn, hubs)

    metadata_kwargs = {}
    if bazel_features.external_deps.extension_metadata_has_reproducible:
        metadata_kwargs["reproducible"] = reproducible
    if facts:
        metadata_kwargs["facts"] = facts

    return module_ctx.extension_metadata(**metadata_kwargs)

_FROM_COMMON_ATTRS = {
    "cargo_config": CRATES_VENDOR_ATTRS["cargo_config"],
    "cargo_lockfile": CRATES_VENDOR_ATTRS["cargo_lockfile"],
    "generate_binaries": CRATES_VENDOR_ATTRS["generate_binaries"],
    "generate_build_scripts": CRATES_VENDOR_ATTRS["generate_build_scripts"],
    "host_tools": attr.label(
        doc = (
            "A repository providing the `bin/cargo` and `bin/rustc` to resolve this hub with, such as one " +
            "created by the `rust_host_tools` extension, in place of the Cargo `crate.host_tools` names or " +
            "the downloaded one. Honored for the root module's hubs only, since resolving runs on the root's " +
            "machine. Only fetched when the hub is resolved."
        ),
    ),
    "isolated": attr.bool(
        doc = (
            "If true, `CARGO_HOME` will be overwritten to a directory within the generated repository in " +
            "order to prevent other uses of Cargo from impacting having any effect on the generated targets " +
            "produced by this rule. For users who either have multiple `crate_repository` definitions in a " +
            "WORKSPACE or rapidly re-pin dependencies, setting this to false may improve build times. This " +
            "variable is also controlled by `CARGO_BAZEL_ISOLATED` environment variable."
        ),
        default = True,
    ),
    "lockfile": attr.label(
        doc = (
            "The path to a file to use for reproducible renderings. " +
            "If set, this file must exist within the workspace (but can be empty) before this rule will work. " +
            "Without one the resolution is kept in the extension's facts in `MODULE.bazel.lock` instead, " +
            "and redone only when its inputs change. A lockfile shipped by a dependency module is used " +
            "as it is and never modified; a dependency module without one is resolved by the root module, " +
            "from its `cargo_lockfile` when it has one, and the resolution kept in the root's facts."
        ),
    ),
    "lockfile_mode": attr.string(
        doc = LOCKFILE_MODE_DOC,
        values = LOCKFILE_MODES,
        default = "update",
    ),
    "skip_cargo_lockfile_overwrite": attr.bool(
        doc = (
            "Whether to skip writing the cargo lockfile back after resolving. " +
            "You may want to set this if your dependency versions are maintained externally through a non-trivial set-up. " +
            "But you probably don't want to set this."
        ),
        default = False,
    ),
    "strip_internal_dependencies_from_cargo_lockfile": attr.bool(
        doc = (
            "Whether to strip internal dependencies from the cargo lockfile. " +
            "You may want to use this if you want to maintain a cargo lockfile for bazel only. " +
            "Bazel only requires external dependencies to be present in the lockfile. " +
            "By removing internal dependencies, the lockfile changes less frequently which reduces merge conflicts " +
            "in other lockfiles where the cargo lockfile's sha is stored."
        ),
        default = False,
    ),
    "supported_platform_triples": attr.string_list(
        doc = "A set of all platform triples to consider when generating dependencies.",
        default = SUPPORTED_PLATFORM_TRIPLES,
    ),
}

_from_cargo = tag_class(
    doc = "Generates a repo @crates from a Cargo.toml / Cargo.lock pair.",
    # Ordering is controlled for readability in generated docs.
    attrs = {
        "name": attr.string(
            doc = "The name of the repo to generate",
            default = "crates",
        ),
    } | {
        "manifests": CRATES_VENDOR_ATTRS["manifests"],
    } | _FROM_COMMON_ATTRS,
)

# This should be kept in sync with crate_universe/private/crate.bzl.
_ANNOTATION_ATTRS = {
    "crate": attr.string(
        doc = "The name of the crate the annotation is applied to",
        mandatory = True,
    ),
    "labels": attr.label_keyed_string_dict(
        doc = (
            "Labels which the annotation's strings may reference by name. Every `@{name}` in a string " +
            "attribute (`build_script_env`, `rustc_env`, `additive_build_file_content`, ...) is replaced " +
            "with the canonical form of the label mapped to `name`. E.g. `labels = {\"@openssl//:install\": " +
            "\"openssl\"}` with `build_script_env = {\"OPENSSL_DIR\": \"$(execpath @{openssl})\"}`. This is " +
            "needed because strings are copied into a generated repository whose repository mapping does not " +
            "include the calling module's dependencies."
        ),
    ),
    "repositories": attr.string_list(
        doc = (
            "A list of repository names specified from `crate.from_cargo(name=...)` that this annotation is " +
            "applied to. Defaults to every repository defined by the same module. `[\"*\"]` applies it to " +
            "every repository of every module and may only be used by the root module."
        ),
        default = [],
    ),
    "version": attr.string(
        doc = "The versions of the crate the annotation is applied to. Defaults to all versions.",
        default = "*",
    ),
}

_ANNOTATION_NORMAL_ATTRS = {
    "additive_build_file": attr.label(
        doc = "A file containing extra contents to write to the bottom of generated BUILD files.",
    ),
    "additive_build_file_content": attr.string(
        doc = "Extra contents to write to the bottom of generated BUILD files.",
    ),
    "alias_rule": attr.string(
        doc = "Alias rule to use instead of `native.alias()`.  Overrides [render_config](#render_config)'s 'default_alias_rule'.",
    ),
    "build_script_data_glob": attr.string_list(
        doc = "A list of glob patterns to add to a crate's `cargo_build_script::data` attribute",
    ),
    "build_script_toolchains": attr.label_list(
        doc = "A list of labels to set on a crates's `cargo_build_script::toolchains` attribute.",
    ),
    "build_script_use_cc_toolchain": attr.string(
        doc = (
            "Whether or not to pull in the resolved `cc_toolchain` when running the build script. " +
            "Supported values are `on`, `off`, and `auto`. Setting `auto` (the default) defers to the " +
            "`@rules_rust//cargo/settings:use_cc_toolchain` build setting (defaults to enabled)."
        ),
        values = _OPT_BOOL_VALUES.keys(),
        default = "auto",
    ),
    "build_script_use_default_shell_env": attr.string(
        doc = (
            "Whether or not to include the default shell environment for the build script action. " +
            "Supported values are `on`, `off`, and `auto`. Setting `auto` (the default) defers to the " +
            "`@rules_rust//cargo/settings:use_default_shell_env` build setting."
        ),
        values = _OPT_BOOL_VALUES.keys(),
        default = "auto",
    ),
    "compile_data_glob": attr.string_list(
        doc = "A list of glob patterns to add to a crate's `rust_library::compile_data` attribute.",
    ),
    "compile_data_glob_excludes": attr.string_list(
        doc = "A list of glob patterns to be excllued from a crate's `rust_library::compile_data` attribute.",
    ),
    "data_glob": attr.string_list(
        doc = "A list of glob patterns to add to a crate's `rust_library::data` attribute.",
    ),
    "disable_pipelining": attr.bool(
        doc = "If True, disables pipelining for library targets for this crate.",
    ),
    "extra_aliased_targets": attr.string_dict(
        doc = "A list of targets to add to the generated aliases in the root crate_universe repository.",
    ),
    "gen_all_binaries": attr.bool(
        doc = "If true, generates `rust_binary` targets for all of the crates bins",
    ),
    "gen_binaries": attr.string_list(
        doc = "As a list, the subset of the crate's bins that should get `rust_binary` targets produced.",
    ),
    "gen_build_script": attr.string(
        doc = "An authoritative flag to determine whether or not to produce `cargo_build_script` targets for the current crate. Supported values are 'on', 'off', and 'auto'.",
        values = _OPT_BOOL_VALUES.keys(),
        default = "auto",
    ),
    "override_target_bin": attr.label(
        doc = "An optional alternate target to use when something depends on this crate to allow the parent repo to provide its own version of this dependency.",
    ),
    "override_target_build_script": attr.label(
        doc = "An optional alternate target to use when something depends on this crate to allow the parent repo to provide its own version of this dependency.",
    ),
    "override_target_lib": attr.label(
        doc = "An optional alternate target to use when something depends on this crate to allow the parent repo to provide its own version of this dependency.",
    ),
    "override_target_proc_macro": attr.label(
        doc = "An optional alternate target to use when something depends on this crate to allow the parent repo to provide its own version of this dependency.",
    ),
    "patch_args": attr.string_list(
        doc = "The `patch_args` attribute of a Bazel repository rule. See [http_archive.patch_args](https://docs.bazel.build/versions/main/repo/http.html#http_archive-patch_args)",
    ),
    "patch_tool": attr.string(
        doc = "The `patch_tool` attribute of a Bazel repository rule. See [http_archive.patch_tool](https://docs.bazel.build/versions/main/repo/http.html#http_archive-patch_tool)",
    ),
    "patches": attr.label_list(
        doc = "The `patches` attribute of a Bazel repository rule. See [http_archive.patches](https://docs.bazel.build/versions/main/repo/http.html#http_archive-patches)",
    ),
    "shallow_since": attr.string(
        doc = "An optional timestamp used for crates originating from a git repository instead of a crate registry. This flag optimizes fetching the source code.",
    ),
}

def _label_list_attrs(name, doc):
    """A label list attribute paired with a `<name>_str` string list.

    `attr.label_list` resolves through the calling module's repository mapping,
    which is what a reference to another module's target needs, and yields the
    canonical form, which is valid from any repository. It cannot express a
    target which only exists inside the generated crate repository, such as one
    declared by `additive_build_file`: `":foo"` would resolve against the calling
    module rather than the generated repository. The `_str` form is written
    verbatim for exactly that case.

    Args:
        name (str): The attribute name.
        doc (str): The attribute documentation.

    Returns:
        dict: The two attributes.
    """
    return {
        name: attr.label_list(doc = doc),
        name + "_str": attr.string_list(
            doc = (
                "Like `{}`, but strings written verbatim into the generated BUILD file. For targets " +
                "which only exist in the generated repository, such as those declared by `additive_build_file`."
            ).format(name),
        ),
    }

# The documentation of every annotation attribute which takes labels. Each is
# declared through `_label_list_attrs` and so has a `_str` counterpart.
_LABEL_LIST_ATTR_DOCS = {
    "build_script_compile_data": "A list of labels to add to a crate's `cargo_build_script::compile_data` attribute.",
    "build_script_data": "A list of labels to add to a crate's `cargo_build_script::data` attribute.",
    "build_script_deps": "A list of labels to add to a crate's `cargo_build_script::deps` attribute.",
    "build_script_env_files": "A list of labels to set on a crate's `cargo_build_script::build_script_env_files` attribute.",
    "build_script_link_deps": "A list of labels to add to a crate's `cargo_build_script::link_deps` attribute.",
    "build_script_proc_macro_deps": "A list of labels to add to a crate's `cargo_build_script::proc_macro_deps` attribute.",
    "build_script_tools": "A list of labels to add to a crate's `cargo_build_script::tools` attribute.",
    "compile_data": "A list of labels to add to a crate's `rust_library::compile_data` attribute.",
    "data": "A list of labels to add to a crate's `rust_library::data` attribute.",
    "deps": "A list of labels to add to a crate's `rust_library::deps` attribute.",
    "link_deps": "A list of labels to add to a crate's `rust_library::link_deps` attribute.",
    "proc_macro_deps": "A list of labels to add to a crate's `rust_library::proc_macro_deps` attribute.",
    "rustc_env_files": "A list of labels to set on a crate's `rust_library::rustc_env_files` attribute.",
}

# The names of every annotation attribute which takes labels.
_LABEL_LIST_ATTRS = _LABEL_LIST_ATTR_DOCS.keys()

_ANNOTATION_SELECT_ATTRS = {
    "build_script_env": attr.string_dict(
        doc = "Additional environment variables to set on a crate's `cargo_build_script::env` attribute.",
    ),
    "build_script_exec_properties": attr.string_dict(
        doc = "Execution properties to set on a crate's `cargo_build_script::exec_properties` attribute.",
    ),
    "build_script_rundir": attr.string(
        doc = "An override for the build script's rundir attribute.",
    ),
    "build_script_rustc_env": attr.string_dict(
        doc = "Additional environment variables to set on a crate's `cargo_build_script::env` attribute.",
    ),
    "crate_features": attr.string_list(
        doc = "A list of strings to add to a crate's `rust_library::crate_features` attribute.",
    ),
    "rustc_env": attr.string_dict(
        doc = "Additional variables to set on a crate's `rust_library::rustc_env` attribute.",
    ),
    "rustc_flags": attr.string_list(
        doc = "A list of strings to set on a crate's `rust_library::rustc_flags` attribute.",
    ),
} | {
    attr_name: attr_def
    for name, doc in _LABEL_LIST_ATTR_DOCS.items()
    for attr_name, attr_def in _label_list_attrs(name, doc).items()
}

_annotation = tag_class(
    doc = "A collection of extra attributes and settings for a particular crate.",
    attrs = _ANNOTATION_ATTRS | _ANNOTATION_NORMAL_ATTRS | _ANNOTATION_SELECT_ATTRS,
)

_from_specs = tag_class(
    doc = (
        "Generates a repo @crates from the defined `spec` tags. Meant for simple sets of " +
        "dependencies; prefer `from_cargo` with a `Cargo.toml` which declares them otherwise."
    ),
    attrs = {
        "name": attr.string(
            doc = "The name of the repo to generate.",
            default = "crates",
        ),
    } | _FROM_COMMON_ATTRS,
)

# This should be kept in sync with crate_universe/private/crate.bzl.
_spec = tag_class(
    doc = "A constructor for a crate dependency.",
    attrs = {
        "artifact": attr.string(
            doc = "Set to 'bin' to pull in a binary crate as an artifact dependency. Requires a nightly Cargo.",
        ),
        "branch": attr.string(
            doc = "The git branch of the remote crate. Tied with the `git` param. Only one of branch, tag or rev may be specified. Specifying `rev` is recommended for fully-reproducible builds.",
        ),
        "default_features": attr.bool(
            doc = "Maps to the `default-features` flag.",
            default = True,
        ),
        "features": attr.string_list(
            doc = "A list of features to use for the crate.",
        ),
        "git": attr.string(
            doc = "The Git url to use for the crate. Cannot be used with `version` or `path`.",
        ),
        "lib": attr.bool(
            doc = "If using `artifact = 'bin'`, additionally setting `lib = True` declares a dependency on both the package's library and binary, as opposed to just the binary.",
        ),
        "package": attr.string(
            doc = "The explicit name of the package.",
            mandatory = True,
        ),
        "package_alias": attr.string(
            doc = "Alias for the package.",
        ),
        "path": attr.string(
            doc = "The local path of the remote crate. Cannot be used with `version` or `git`.",
        ),
        "repositories": attr.string_list(
            doc = "A list of repository names specified from `crate.from_cargo(name=...)` that this spec is applied to. Defaults to every repository defined by the same module.",
            default = [],
        ),
        "rev": attr.string(
            doc = "The git revision of the remote crate. Tied with the `git` param. Only one of branch, tag or rev may be specified.",
        ),
        "tag": attr.string(
            doc = "The git tag of the remote crate. Tied with the `git` param. Only one of branch, tag or rev may be specified. Specifying `rev` is recommended for fully-reproducible builds.",
        ),
        "version": attr.string(
            doc = "The exact version of the crate. Cannot be used with `git` or `path`.",
        ),
    },
)

_splicing_config = tag_class(
    doc = "Various settings used to configure Cargo manifest splicing behavior.",
    attrs = {
        "repositories": attr.string_list(
            doc = (
                "A list of repository names specified from `crate.from_cargo(name=...)` that this annotation is " +
                "applied to. Defaults to every repository defined by the same module. `[\"*\"]` applies it to " +
                "every repository of every module and may only be used by the root module."
            ),
            default = [],
        ),
    } | {
        "resolver_version": attr.string(
            doc = "The [resolver version](https://doc.rust-lang.org/cargo/reference/resolver.html#resolver-versions) to use in generated Cargo manifests. This flag is **only** used when splicing a manifest from direct package definitions. See `crates_repository::packages`",
            default = "2",
        ),
    },
)

_host_tools = tag_class(
    doc = """\
The Cargo the root module resolves every hub with.

Resolving crates runs Cargo on the machine running Bazel. By default that is a
Cargo the `rust` extension downloads for the host on its own, at rules_rust's
default Rust version, from the Rust distribution; it runs wherever those
binaries run. A root module whose host
cannot run them, a NixOS host without `nix-ld` for example, names a Cargo built
for the host instead, such as one `rules_nixpkgs` provides:

```python
crate.host_tools(cargo = "@nix_cargo//:bin/cargo")
```

Resolving needs Cargo alone: `cargo-bazel` stands in for rustc. A `rustc` is
consulted only for platforms with no recorded `rustc --print=cfg`, and a nightly
Cargo is needed for `-Zbindeps`. A hub's own `host_tools` overrides this for
that hub. Only the root module may use this tag.
""",
    attrs = {
        "cargo": attr.label(
            doc = "The `cargo` binary to resolve with.",
            mandatory = True,
        ),
        "rustc": attr.label(
            doc = "A `rustc` to pair with it, for platforms with no recorded `rustc --print=cfg`.",
        ),
    },
)

_render_config = tag_class(
    doc = """\
Various settings used to configure rendered outputs.

The template parameters each support a select number of format keys. A description of each key
can be found below where the supported keys for each template can be found in the parameter docs

| key | definition |
| --- | --- |
| `name` | The name of the crate. Eg `tokio` |
| `repository` | The rendered repository name for the crate. Directly relates to `crate_repository_template`. |
| `triple` | A platform triple. Eg `x86_64-unknown-linux-gnu` |
| `version` | The crate version. Eg `1.2.3` |
| `target` | The library or binary target of the crate |
| `file` | The basename of a file |
""",
    attrs = {
        "repositories": attr.string_list(
            doc = (
                "A list of repository names specified from `crate.from_cargo(name=...)` that this annotation is " +
                "applied to. Defaults to every repository defined by the same module. `[\"*\"]` applies it to " +
                "every repository of every module and may only be used by the root module."
            ),
            default = [],
        ),
    } | {
        "build_file_template": attr.string(
            doc = "The base template to use for BUILD file names. The available format keys are [`{name}`, {version}`].",
            default = "//:BUILD.{name}-{version}.bazel",
        ),
        "crate_alias_template": attr.string(
            doc = (
                "The base template to use for crate aliases. The available format keys are " +
                "[`{repository}`, `{name}`, `{version}`, `{target}`]. Defaults to the per-alias " +
                "subpackage layout (`@{repository}//{name}-{version}`)."
            ),
            default = "@{repository}//{name}-{version}",
        ),
        "crate_label_template": attr.string(
            doc = "The base template to use for crate labels. The available format keys are [`{repository}`, `{name}`, `{version}`, `{target}`].",
            default = "@{repository}__{name}-{version}//:{target}",
        ),
        "crate_repository_template": attr.string(
            doc = "The base template to use for Crate label repository names. The available format keys are [`{repository}`, `{name}`, `{version}`].",
            default = "{repository}__{name}-{version}",
        ),
        "crates_module_template": attr.string(
            doc = "The pattern to use for the `defs.bzl` and `BUILD.bazel` file names used for the crates module. The available format keys are [`{file}`].",
            default = "//:{file}",
        ),
        "default_alias_rule_bzl": attr.label(
            doc = "Alias rule to use when generating aliases for all crates.  Acceptable values are 'alias', 'dbg'/'fastbuild'/'opt' (transitions each crate's `compilation_mode`)  or a string representing a rule in the form '<label to .bzl>:<rule>' that takes a single label parameter 'actual'. See '@crate_index//:alias_rules.bzl' for an example.",
        ),
        "default_alias_rule_name": attr.string(
            doc = "Alias rule to use when generating aliases for all crates.  Acceptable values are 'alias', 'dbg'/'fastbuild'/'opt' (transitions each crate's `compilation_mode`)  or a string representing a rule in the form '<label to .bzl>:<rule>' that takes a single label parameter 'actual'. See '@crate_index//:alias_rules.bzl' for an example.",
            default = "alias",
        ),
        "default_package_name": attr.string(
            doc = "The default package name to use in the rendered macros. This affects the auto package detection of things like `all_crate_deps`.",
            default = "",
        ),
        "generate_cargo_toml_env_vars": attr.bool(
            doc = "Whether to generate cargo_toml_env_vars targets. Build-wide: honored only on the root module's `render_config(repositories = [\"*\"])`.",
            default = True,
        ),
        "generate_rules_license_metadata": attr.bool(
            doc = (
                "Whether every crate's BUILD file declares its identity and license as `package_metadata`: " +
                "a rules_license `package_info` (name, version, URL, purl) and, when the crate declares a " +
                "license, a `license` with the SPDX kinds rules_license knows and the license text. Each hub " +
                "subpackage aliases them as `@<hub>//<crate>:package_info` and `@<hub>//<crate>:license`. " +
                "Build-wide: honored only on the root module's `render_config(repositories = [\"*\"])`."
            ),
            default = True,
        ),
        "generate_target_compatible_with": attr.bool(
            doc = "Whether to generate `target_compatible_with` annotations on the generated BUILD files.  This catches a `target_triple` being targeted that isn't declared in `supported_platform_triples`.",
            default = True,
        ),
        "platforms_template": attr.string(
            doc = (
                "The base template for the `select()` keys of platform specific dependencies. The available " +
                "format key is `{triple}`. Build-wide: honored only on the root module's " +
                "`render_config(repositories = [\"*\"])`, so every hub, including those of dependencies, " +
                "renders against the platforms this build registers. The package it points at must hold one " +
                "`config_setting`, `config_setting_group` or `alias` per triple, named by the triple; " +
                "`declare_platform_aliases` from `@rules_rust//rust/platform:platform.bzl` declares them, " +
                "with overrides for the triples this build distinguishes further."
            ),
            default = "@rules_rust//rust/platform:{triple}",
        ),
        "regen_command": attr.string(
            doc = "An optional command to demonstrate how generated files should be regenerated.",
            default = "",
        ),
        "vendor_mode": attr.string(
            doc = "An optional configuration for rendering content to be rendered into repositories.",
            default = "",
        ),
    },
)

_annotation_select = tag_class(
    doc = "A constructor for a crate dependency with selectable attributes.",
    attrs = _ANNOTATION_ATTRS | {
        "triples": attr.string_list(
            doc = "A list of triples to apply the annotation to.",
            mandatory = True,
        ),
    } | _ANNOTATION_SELECT_ATTRS,
)

crate = module_extension(
    doc = """\
Crate universe module extensions.

Environment Variables:

| variable | usage |
| --- | --- |
| `CARGO_BAZEL_GENERATOR_SHA256` | The sha256 checksum of the file located at `CARGO_BAZEL_GENERATOR_URL` |
| `CARGO_BAZEL_GENERATOR_URL` | The URL of a cargo-bazel binary. This variable takes precedence over attributes and can use `file://` for local paths |
| `CARGO_BAZEL_ISOLATED` | An authoritative flag as to whether or not the `CARGO_HOME` environment variable should be isolated from the host configuration |
| `CARGO_BAZEL_REPIN` | An indicator that the dependencies represented by the rule should be regenerated. `REPIN` may also be used. See [Repinning / Updating Dependencies](crate_universe_workspace.html#repinning--updating-dependencies) for more details. |
| `CARGO_BAZEL_REPIN_ONLY` | A comma-delimited allowlist for rules to execute repinning. Can be useful if multiple instances of the repository rule are used in a Bazel workspace, but repinning should be limited to one of them. |
| `CARGO_BAZEL_TIMEOUT` | An integer value to override the default timeout setting when running the cargo-bazel binary. This value must be in seconds. |

""",
    implementation = _crate_impl,
    tag_classes = {
        "annotation": _annotation,
        "annotation_select": _annotation_select,
        "from_cargo": _from_cargo,
        "from_specs": _from_specs,
        "host_tools": _host_tools,
        "render_config": _render_config,
        "spec": _spec,
        "splicing_config": _splicing_config,
    },
    environ = CRATES_REPOSITORY_ENVIRON,
)
