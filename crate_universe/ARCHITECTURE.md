# What crate_universe renders

`crate_universe` turns a Cargo resolution into Bazel repositories. This page
describes the repositories the `crate` module extension declares and how they
refer to each other, so a change to the renderer can be checked against the
intended shape. The diagram is maintained by hand. When the renderer or the
extension changes what is rendered, update it in the same change.

Every `crate.from_cargo` or `crate.from_specs` tag declares one hub, a
repository whose files only point at crates. The crates themselves live in
repositories pooled across every hub of the build. A crate's repository is named
after the crate and the hash of its closure, everything that shapes its BUILD
file, so two hubs that resolved the same `serde` with the same features and
dependencies share one repository and compile it once. See `src/pool.rs` for the
closure and `cargo-bazel pool` for the rendering.

```mermaid
flowchart LR
    subgraph consumer["Consumer BUILD files"]
        dep["rust_library(deps = ['@crates//serde'])"]
        bin["@crates//clap__clap (a crate's binary)"]
    end

    subgraph hub["Hub repository, one per tag: @crates"]
        hub_build["BUILD.bazel<br/>exports_files, :srcs filegroup"]
        crates_bzl["crates.bzl<br/>aliases(), all_crate_deps(), crate_deps(),<br/>crate_edition() per workspace member;<br/>crate_repositories()"]
        defs["defs.bzl<br/>deprecated re-export of crates.bzl"]
        sub_serde["serde/BUILD.bazel<br/>alias(actual = '@serde-1.0.229-f362ca40f0//:serde')"]
        sub_clap["clap__clap/BUILD.bazel<br/>alias(actual = '@clap-4.5.37-…//:clap__bin')"]
    end

    subgraph pool["Pooled crate repositories, shared by every hub"]
        serde["@serde-1.0.229-f362ca40f0<br/>http_archive<br/>rust_library :serde<br/>cargo_build_script :build_script_build"]
        serde_derive["@serde_derive-1.0.229-…<br/>http_archive<br/>rust_proc_macro :serde_derive"]
        names["@names-0.13.0-…<br/>http_archive of a GitHub commit<br/>rust_library :names"]
        local["@my_lib-0.1.0-…<br/>local_crate_mirror (path dependency)"]
    end

    subgraph sources["Where the archives come from"]
        registry["static.crates.io/crates/&lt;name&gt;/&lt;version&gt;/download"]
        github["github.com/&lt;owner&gt;/&lt;repo&gt;/archive/&lt;commit&gt;.tar.gz"]
        git["git_repository, for git sources not on GitHub<br/>or declaring submodules"]
    end

    dep --> sub_serde --> serde
    bin --> sub_clap
    crates_bzl -. "aliases()" .-> sub_serde
    serde -- "proc_macro_deps" --> serde_derive
    serde -- "deps, by closure name" --> names
    serde --> registry
    serde_derive --> registry
    names --> github
    local -. "symlinked from the workspace" .-> consumer
    git ~~~ sources
```

## The hub

| File | Contents |
| --- | --- |
| `BUILD.bazel` | `exports_files` for the module files and a `:srcs` filegroup. No targets of its own: `@hub//:name` does not exist, `@hub//name` does. |
| `crates.bzl` | The dependency macros, `aliases()`, `all_crate_deps()`, `crate_deps()` and `crate_edition()`, keyed by the workspace member calling them, and `crate_repositories()`, which declares the crate repositories for `crates_repository` and `crates_vendor`. The extension declares them itself. |
| `defs.bzl` | Deprecated. Re-exports the macros of `crates.bzl`. |
| `<crate>/BUILD.bazel` | One subpackage per crate a workspace member depends on, holding an `alias` to the crate's library target in its pooled repository, plus aliases to its `package_info` and `license` targets. `aliases()` renames resolve through these. |
| `<crate>__<bin>/BUILD.bazel` | One subpackage per binary of a crate with `gen_binaries`, aliasing the `rust_binary`. |

## A pooled crate repository

Named `<name>-<version>-<closure>`. Its `BUILD.bazel` is rendered from the
crate's resolved context under a hub independent configuration, so equal
closures render identically whichever hub produced them. `pool` fails if two
hubs disagree, which means the closure hash is missing an input. It holds:

- `rust_library` or `rust_proc_macro` for the library target, with
  `crate_features`, `deps` and `proc_macro_deps` pointing at other pooled
  repositories by their closure names, split by platform with `select()` on the
  platform labels the root module configured;
- `cargo_build_script` and the `build_script_build` target when the crate has a
  build script, plus the `links` dependencies it needs;
- `rust_binary` targets when binaries are requested;
- `cargo_toml_env_vars` when enabled, so `CARGO_PKG_*` match the manifest;
- `package_info` and, when the crate declares one, `license`, set as the
  `package_metadata` of every target.

The repository rule follows the crate's source. Registry crates and git
dependencies hosted on GitHub are `http_archive`s, the latter of the pinned
commit's archive with a checksum. Other git sources and repositories declaring
submodules are `git_repository`s. Path dependencies are `local_crate_mirror`s,
which copy the workspace directory and add the rendered BUILD file.

`crates_repository` and `crates_vendor` render the same hub files but their own
crate repositories, named `<hub>__<name>-<version>`, since there is no module
extension to pool across. Local vendoring (`crates_vendor(mode = "local")`)
writes the crates' sources and BUILD files into the workspace in place of
repositories.
