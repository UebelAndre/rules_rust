<!-- Generated with Stardoc: http://skydoc.bazel.build -->
# Rust Repositories

* [rust_repositories](#rust_repositories)
* [rust_repositories](#rust_repositories)
* [rust_exec_toolchain_repository](#rust_exec_toolchain_repository)
* [rust_target_toolchain_repository](#rust_target_toolchain_repository)
* [rust_rustc_repository](#rust_rustc_repository)
* [rust_clippy_repository](#rust_clippy_repository)
* [rust_cargo_repository](#rust_cargo_repository)
* [rust_rustfmt_repository](#rust_rustfmt_repository)
* [rust_exec_toolchain](#rust_exec_toolchain)
* [rust_target_toolchain](#rust_target_toolchain)
* [rust_cargo_toolchain](#rust_cargo_toolchain)
* [rust_clippy_toolchain](#rust_clippy_toolchain)
* [rust_rustfmt_toolchain](#rust_rustfmt_toolchain)
* [toolchain_tool](#toolchain_tool)

<a id="#rust_cargo_repository"></a>

## rust_cargo_repository

<pre>
rust_cargo_repository(<a href="#rust_cargo_repository-name">name</a>, <a href="#rust_cargo_repository-iso_date">iso_date</a>, <a href="#rust_cargo_repository-repo_mapping">repo_mapping</a>, <a href="#rust_cargo_repository-sha256">sha256</a>, <a href="#rust_cargo_repository-triple">triple</a>, <a href="#rust_cargo_repository-urls">urls</a>, <a href="#rust_cargo_repository-version">version</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="rust_cargo_repository-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="rust_cargo_repository-iso_date"></a>iso_date |  The date of the tool (or None, if the version is a specific version).   | String | optional | "" |
| <a id="rust_cargo_repository-repo_mapping"></a>repo_mapping |  A dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.&lt;p&gt;For example, an entry <code>"@foo": "@bar"</code> declares that, for any time this repository depends on <code>@foo</code> (such as a dependency on <code>@foo//some:target</code>, it should actually resolve that dependency within globally-declared <code>@bar</code> (<code>@bar//some:target</code>).   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | required |  |
| <a id="rust_cargo_repository-sha256"></a>sha256 |  The sha256 of the cargo artifact.   | String | optional | "" |
| <a id="rust_cargo_repository-triple"></a>triple |  The Rust-style target that this compiler runs on   | String | required |  |
| <a id="rust_cargo_repository-urls"></a>urls |  A list of mirror urls containing the tools from the Rust-lang static file server. These must contain the '{}' used to substitute the tool being fetched (using .format).   | List of strings | optional | ["https://static.rust-lang.org/dist/{}.tar.gz"] |
| <a id="rust_cargo_repository-version"></a>version |  The version of the tool among "nightly", "beta", or an exact version.   | String | required |  |


<a id="#rust_cargo_toolchain"></a>

## rust_cargo_toolchain

<pre>
rust_cargo_toolchain(<a href="#rust_cargo_toolchain-name">name</a>, <a href="#rust_cargo_toolchain-cargo">cargo</a>)
</pre>

Declares a Cargo toolchain for use.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="rust_cargo_toolchain-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="rust_cargo_toolchain-cargo"></a>cargo |  The location of the <code>cargo</code> binary.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |


<a id="#rust_clippy_repository"></a>

## rust_clippy_repository

<pre>
rust_clippy_repository(<a href="#rust_clippy_repository-name">name</a>, <a href="#rust_clippy_repository-iso_date">iso_date</a>, <a href="#rust_clippy_repository-repo_mapping">repo_mapping</a>, <a href="#rust_clippy_repository-sha256">sha256</a>, <a href="#rust_clippy_repository-triple">triple</a>, <a href="#rust_clippy_repository-urls">urls</a>, <a href="#rust_clippy_repository-version">version</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="rust_clippy_repository-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="rust_clippy_repository-iso_date"></a>iso_date |  The date of the tool (or None, if the version is a specific version).   | String | optional | "" |
| <a id="rust_clippy_repository-repo_mapping"></a>repo_mapping |  A dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.&lt;p&gt;For example, an entry <code>"@foo": "@bar"</code> declares that, for any time this repository depends on <code>@foo</code> (such as a dependency on <code>@foo//some:target</code>, it should actually resolve that dependency within globally-declared <code>@bar</code> (<code>@bar//some:target</code>).   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | required |  |
| <a id="rust_clippy_repository-sha256"></a>sha256 |  The sha256 of the clippy-driver artifact.   | String | optional | "" |
| <a id="rust_clippy_repository-triple"></a>triple |  The Rust-style target that this compiler runs on   | String | required |  |
| <a id="rust_clippy_repository-urls"></a>urls |  A list of mirror urls containing the tools from the Rust-lang static file server. These must contain the '{}' used to substitute the tool being fetched (using .format).   | List of strings | optional | ["https://static.rust-lang.org/dist/{}.tar.gz"] |
| <a id="rust_clippy_repository-version"></a>version |  The version of the tool among "nightly", "beta", or an exact version.   | String | required |  |


<a id="#rust_clippy_toolchain"></a>

## rust_clippy_toolchain

<pre>
rust_clippy_toolchain(<a href="#rust_clippy_toolchain-name">name</a>, <a href="#rust_clippy_toolchain-clippy_driver">clippy_driver</a>)
</pre>

Declares a Clippy toolchain for use.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="rust_clippy_toolchain-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="rust_clippy_toolchain-clippy_driver"></a>clippy_driver |  The location of the <code>clippy-driver</code> binary.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |


<a id="#rust_exec_toolchain"></a>

## rust_exec_toolchain

<pre>
rust_exec_toolchain(<a href="#rust_exec_toolchain-name">name</a>, <a href="#rust_exec_toolchain-os">os</a>, <a href="#rust_exec_toolchain-rustc">rustc</a>, <a href="#rust_exec_toolchain-rustc_lib">rustc_lib</a>, <a href="#rust_exec_toolchain-rustc_srcs">rustc_srcs</a>, <a href="#rust_exec_toolchain-rustdoc">rustdoc</a>, <a href="#rust_exec_toolchain-triple">triple</a>)
</pre>

Declares a Rust exec/host toolchain for use.

This is for declaring a custom toolchain, eg. for configuring a particular version of rust or supporting a new platform.

Example:

Suppose the core rust team has ported the compiler to a new target CPU, called `cpuX`. This     support can be used in Bazel by defining a new toolchain definition and declaration:

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

Then, either add the label of the toolchain rule to `register_toolchains` in the WORKSPACE, or pass     it to the `"--extra_toolchains"` flag for Bazel, and it will be used.

See @rules_rust//rust:repositories.bzl for examples of defining the @rust_cpuX repository     with the actual binaries and libraries.


**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="rust_exec_toolchain-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="rust_exec_toolchain-os"></a>os |  The operating system for the current toolchain   | String | required |  |
| <a id="rust_exec_toolchain-rustc"></a>rustc |  The location of the <code>rustc</code> binary. Can be a direct source or a filegroup containing one item.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |
| <a id="rust_exec_toolchain-rustc_lib"></a>rustc_lib |  The location of the <code>rustc</code> binary. Can be a direct source or a filegroup containing one item.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |
| <a id="rust_exec_toolchain-rustc_srcs"></a>rustc_srcs |  The source code of rustc.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | optional | None |
| <a id="rust_exec_toolchain-rustdoc"></a>rustdoc |  The location of the <code>rustdoc</code> binary. Can be a direct source or a filegroup containing one item.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | optional | None |
| <a id="rust_exec_toolchain-triple"></a>triple |  The platform triple for the toolchains execution environment. For more details see: https://docs.bazel.build/versions/master/skylark/rules.html#configurations   | String | optional | "" |


<a id="#rust_rustc_repository"></a>

## rust_rustc_repository

<pre>
rust_rustc_repository(<a href="#rust_rustc_repository-name">name</a>, <a href="#rust_rustc_repository-dev_components">dev_components</a>, <a href="#rust_rustc_repository-iso_date">iso_date</a>, <a href="#rust_rustc_repository-repo_mapping">repo_mapping</a>, <a href="#rust_rustc_repository-sha256s">sha256s</a>, <a href="#rust_rustc_repository-triple">triple</a>, <a href="#rust_rustc_repository-urls">urls</a>, <a href="#rust_rustc_repository-version">version</a>)
</pre>

must be a host toolchain

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="rust_rustc_repository-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="rust_rustc_repository-dev_components"></a>dev_components |  Whether to download the rustc-dev components (defaults to False). Requires version to be "nightly".   | Boolean | optional | False |
| <a id="rust_rustc_repository-iso_date"></a>iso_date |  The date of the tool (or None, if the version is a specific version).   | String | optional | "" |
| <a id="rust_rustc_repository-repo_mapping"></a>repo_mapping |  A dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.&lt;p&gt;For example, an entry <code>"@foo": "@bar"</code> declares that, for any time this repository depends on <code>@foo</code> (such as a dependency on <code>@foo//some:target</code>, it should actually resolve that dependency within globally-declared <code>@bar</code> (<code>@bar//some:target</code>).   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | required |  |
| <a id="rust_rustc_repository-sha256s"></a>sha256s |  A dict associating tool subdirectories to sha256 hashes. See [rust_repositories](#rust_repositories) for more details.   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | optional | {} |
| <a id="rust_rustc_repository-triple"></a>triple |  The Rust-style target that this compiler runs on   | String | required |  |
| <a id="rust_rustc_repository-urls"></a>urls |  A list of mirror urls containing the tools from the Rust-lang static file server. These must contain the '{}' used to substitute the tool being fetched (using .format).   | List of strings | optional | ["https://static.rust-lang.org/dist/{}.tar.gz"] |
| <a id="rust_rustc_repository-version"></a>version |  The version of the tool among "nightly", "beta", or an exact version.   | String | required |  |


<a id="#rust_rustfmt_repository"></a>

## rust_rustfmt_repository

<pre>
rust_rustfmt_repository(<a href="#rust_rustfmt_repository-name">name</a>, <a href="#rust_rustfmt_repository-iso_date">iso_date</a>, <a href="#rust_rustfmt_repository-repo_mapping">repo_mapping</a>, <a href="#rust_rustfmt_repository-sha256">sha256</a>, <a href="#rust_rustfmt_repository-triple">triple</a>, <a href="#rust_rustfmt_repository-urls">urls</a>, <a href="#rust_rustfmt_repository-version">version</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="rust_rustfmt_repository-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="rust_rustfmt_repository-iso_date"></a>iso_date |  The date of the tool (or None, if the version is a specific version).   | String | optional | "" |
| <a id="rust_rustfmt_repository-repo_mapping"></a>repo_mapping |  A dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.&lt;p&gt;For example, an entry <code>"@foo": "@bar"</code> declares that, for any time this repository depends on <code>@foo</code> (such as a dependency on <code>@foo//some:target</code>, it should actually resolve that dependency within globally-declared <code>@bar</code> (<code>@bar//some:target</code>).   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | required |  |
| <a id="rust_rustfmt_repository-sha256"></a>sha256 |  The sha256 of the rustfmt artifact.   | String | optional | "" |
| <a id="rust_rustfmt_repository-triple"></a>triple |  The Rust-style target that this compiler runs on   | String | required |  |
| <a id="rust_rustfmt_repository-urls"></a>urls |  A list of mirror urls containing the tools from the Rust-lang static file server. These must contain the '{}' used to substitute the tool being fetched (using .format).   | List of strings | optional | ["https://static.rust-lang.org/dist/{}.tar.gz"] |
| <a id="rust_rustfmt_repository-version"></a>version |  The version of the tool among "nightly", "beta", or an exact version.   | String | required |  |


<a id="#rust_rustfmt_toolchain"></a>

## rust_rustfmt_toolchain

<pre>
rust_rustfmt_toolchain(<a href="#rust_rustfmt_toolchain-name">name</a>, <a href="#rust_rustfmt_toolchain-rustfmt">rustfmt</a>)
</pre>

Declares a Rustfmt toolchain for use.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="rust_rustfmt_toolchain-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="rust_rustfmt_toolchain-rustfmt"></a>rustfmt |  The location of the <code>rustfmt</code> binary.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |


<a id="#rust_target_toolchain"></a>

## rust_target_toolchain

<pre>
rust_target_toolchain(<a href="#rust_target_toolchain-name">name</a>, <a href="#rust_target_toolchain-allocator_library">allocator_library</a>, <a href="#rust_target_toolchain-binary_ext">binary_ext</a>, <a href="#rust_target_toolchain-debug_info">debug_info</a>, <a href="#rust_target_toolchain-default_edition">default_edition</a>, <a href="#rust_target_toolchain-dylib_ext">dylib_ext</a>,
                      <a href="#rust_target_toolchain-opt_level">opt_level</a>, <a href="#rust_target_toolchain-os">os</a>, <a href="#rust_target_toolchain-rust_stdlib">rust_stdlib</a>, <a href="#rust_target_toolchain-staticlib_ext">staticlib_ext</a>, <a href="#rust_target_toolchain-stdlib_linkflags">stdlib_linkflags</a>, <a href="#rust_target_toolchain-triple">triple</a>)
</pre>

Declares a Rust target toolchain for use.

This is for declaring a custom toolchain, eg. for configuring a particular version of rust or supporting a new platform.

Example:

Suppose the core rust team has ported the compiler to a new target CPU, called `cpuX`. This     support can be used in Bazel by defining a new toolchain definition and declaration:

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


**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="rust_target_toolchain-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="rust_target_toolchain-allocator_library"></a>allocator_library |  Target that provides allocator functions when rust_library targets are embedded in a cc_binary.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | optional | None |
| <a id="rust_target_toolchain-binary_ext"></a>binary_ext |  The extension for binaries created from rustc.   | String | required |  |
| <a id="rust_target_toolchain-debug_info"></a>debug_info |  Rustc debug info levels per opt level   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | optional | {"dbg": "2", "fastbuild": "0", "opt": "0"} |
| <a id="rust_target_toolchain-default_edition"></a>default_edition |  The edition to use for rust_* rules that don't specify an edition.   | String | optional | "2015" |
| <a id="rust_target_toolchain-dylib_ext"></a>dylib_ext |  The extension for dynamic libraries created from rustc.   | String | required |  |
| <a id="rust_target_toolchain-opt_level"></a>opt_level |  Rustc optimization levels.   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | optional | {"dbg": "0", "fastbuild": "0", "opt": "3"} |
| <a id="rust_target_toolchain-os"></a>os |  The operating system for the current toolchain   | String | required |  |
| <a id="rust_target_toolchain-rust_stdlib"></a>rust_stdlib |  The rust standard library.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |
| <a id="rust_target_toolchain-staticlib_ext"></a>staticlib_ext |  The extension for static libraries created from rustc.   | String | required |  |
| <a id="rust_target_toolchain-stdlib_linkflags"></a>stdlib_linkflags |  Additional linker libs used when std lib is linked, see https://github.com/rust-lang/rust/blob/master/src/libstd/build.rs   | List of strings | required |  |
| <a id="rust_target_toolchain-triple"></a>triple |  The platform triple for the toolchains execution environment. For more details see: https://docs.bazel.build/versions/master/skylark/rules.html#configurations   | String | optional | "" |


<a id="#rust_exec_toolchain_repository"></a>

## rust_exec_toolchain_repository

<pre>
rust_exec_toolchain_repository(<a href="#rust_exec_toolchain_repository-prefix">prefix</a>, <a href="#rust_exec_toolchain_repository-triple">triple</a>, <a href="#rust_exec_toolchain_repository-version">version</a>, <a href="#rust_exec_toolchain_repository-edition">edition</a>, <a href="#rust_exec_toolchain_repository-urls">urls</a>, <a href="#rust_exec_toolchain_repository-iso_date">iso_date</a>, <a href="#rust_exec_toolchain_repository-sha256s">sha256s</a>,
                               <a href="#rust_exec_toolchain_repository-dev_components">dev_components</a>, <a href="#rust_exec_toolchain_repository-include_rustc_srcs">include_rustc_srcs</a>, <a href="#rust_exec_toolchain_repository-rustfmt_version">rustfmt_version</a>, <a href="#rust_exec_toolchain_repository-rustfmt_iso_date">rustfmt_iso_date</a>)
</pre>

[summary]

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="rust_exec_toolchain_repository-prefix"></a>prefix |  [description]   |  none |
| <a id="rust_exec_toolchain_repository-triple"></a>triple |  [description]   |  none |
| <a id="rust_exec_toolchain_repository-version"></a>version |  [description]. Defaults to DEFAULT_RUST_VERSION.   |  <code>"1.53.0"</code> |
| <a id="rust_exec_toolchain_repository-edition"></a>edition |  [description]. Defaults to DEFAULT_RUST_EDITION.   |  <code>"2015"</code> |
| <a id="rust_exec_toolchain_repository-urls"></a>urls |  [description]. Defaults to DEFAULT_STATIC_RUST_URL_TEMPLATES.   |  <code>["https://static.rust-lang.org/dist/{}.tar.gz"]</code> |
| <a id="rust_exec_toolchain_repository-iso_date"></a>iso_date |  [description]. Defaults to None.   |  <code>None</code> |
| <a id="rust_exec_toolchain_repository-sha256s"></a>sha256s |  [description]. Defaults to None.   |  <code>None</code> |
| <a id="rust_exec_toolchain_repository-dev_components"></a>dev_components |  [description]. Defaults to False.   |  <code>False</code> |
| <a id="rust_exec_toolchain_repository-include_rustc_srcs"></a>include_rustc_srcs |  [description]. Defaults to False.   |  <code>False</code> |
| <a id="rust_exec_toolchain_repository-rustfmt_version"></a>rustfmt_version |  [description]. Defaults to None.   |  <code>None</code> |
| <a id="rust_exec_toolchain_repository-rustfmt_iso_date"></a>rustfmt_iso_date |  [description]. Defaults to None.   |  <code>None</code> |


<a id="#rust_repositories"></a>

## rust_repositories

<pre>
rust_repositories(<a href="#rust_repositories-version">version</a>, <a href="#rust_repositories-iso_date">iso_date</a>, <a href="#rust_repositories-rustfmt_version">rustfmt_version</a>, <a href="#rust_repositories-edition">edition</a>, <a href="#rust_repositories-dev_components">dev_components</a>, <a href="#rust_repositories-sha256s">sha256s</a>,
                  <a href="#rust_repositories-include_rustc_srcs">include_rustc_srcs</a>, <a href="#rust_repositories-urls">urls</a>)
</pre>

[summary]

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="rust_repositories-version"></a>version |  [description]. Defaults to DEFAULT_RUST_VERSION.   |  <code>"1.53.0"</code> |
| <a id="rust_repositories-iso_date"></a>iso_date |  [description]. Defaults to None.   |  <code>None</code> |
| <a id="rust_repositories-rustfmt_version"></a>rustfmt_version |  [description]. Defaults to None.   |  <code>None</code> |
| <a id="rust_repositories-edition"></a>edition |  [description]. Defaults to DEFAULT_RUST_EDITION.   |  <code>"2015"</code> |
| <a id="rust_repositories-dev_components"></a>dev_components |  [description]. Defaults to False.   |  <code>False</code> |
| <a id="rust_repositories-sha256s"></a>sha256s |  [description]. Defaults to None.   |  <code>None</code> |
| <a id="rust_repositories-include_rustc_srcs"></a>include_rustc_srcs |  [description]. Defaults to False.   |  <code>False</code> |
| <a id="rust_repositories-urls"></a>urls |  [description]. Defaults to DEFAULT_STATIC_RUST_URL_TEMPLATES.   |  <code>["https://static.rust-lang.org/dist/{}.tar.gz"]</code> |


<a id="#rust_target_toolchain_repository"></a>

## rust_target_toolchain_repository

<pre>
rust_target_toolchain_repository(<a href="#rust_target_toolchain_repository-prefix">prefix</a>, <a href="#rust_target_toolchain_repository-triple">triple</a>, <a href="#rust_target_toolchain_repository-version">version</a>, <a href="#rust_target_toolchain_repository-urls">urls</a>, <a href="#rust_target_toolchain_repository-allocator_library">allocator_library</a>, <a href="#rust_target_toolchain_repository-iso_date">iso_date</a>,
                                 <a href="#rust_target_toolchain_repository-sha256s">sha256s</a>)
</pre>

[summary]

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="rust_target_toolchain_repository-prefix"></a>prefix |  [description]   |  none |
| <a id="rust_target_toolchain_repository-triple"></a>triple |  [description]   |  none |
| <a id="rust_target_toolchain_repository-version"></a>version |  [description]. Defaults to DEFAULT_RUST_VERSION.   |  <code>"1.53.0"</code> |
| <a id="rust_target_toolchain_repository-urls"></a>urls |  [description]. Defaults to DEFAULT_STATIC_RUST_URL_TEMPLATES.   |  <code>["https://static.rust-lang.org/dist/{}.tar.gz"]</code> |
| <a id="rust_target_toolchain_repository-allocator_library"></a>allocator_library |  [description]. Defaults to None.   |  <code>None</code> |
| <a id="rust_target_toolchain_repository-iso_date"></a>iso_date |  [description]. Defaults to None.   |  <code>None</code> |
| <a id="rust_target_toolchain_repository-sha256s"></a>sha256s |  [description]. Defaults to None.   |  <code>None</code> |


