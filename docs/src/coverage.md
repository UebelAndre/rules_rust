# Code Coverage

Rules Rust supports collecting code coverage data using `bazel coverage`, leveraging LLVM's source-based coverage instrumentation.

## Basic Usage

```sh
bazel coverage //my_project/...
```

This instruments all targets matching the default `--instrumentation_filter` and produces an LCOV report at `bazel-out/_coverage/_coverage_report.dat`.

## Controlling Instrumentation

Rules Rust respects Bazel's standard [`--instrumentation_filter`](https://bazel.build/reference/command-line-reference#flag--instrumentation_filter) flag to control which targets get compiled with `-Cinstrument-coverage`. Only targets whose label matches the filter are instrumented, consistent with how coverage works for other languages (C++, Java).

### Recommended `.bazelrc` Settings

For projects with vendored or third-party dependencies, restrict instrumentation to workspace targets to avoid unnecessary recompilation:

```text
coverage --instrumentation_filter=^//
```

To further exclude specific directories:

```text
coverage --instrumentation_filter=^//,-^//third_party
```

### `rust_test` with a `crate` attribute

When a `rust_test` target uses the `crate` attribute, Rust compiles the library source code directly into the test binary. Rules Rust automatically checks whether the underlying crate should be instrumented, so library code compiled into the test binary produces coverage data without needing `--instrument_test_targets`.

Note: because the entire crate (including `#[cfg(test)]` code) is compiled as one unit, test-specific code in the crate will also be instrumented. This is a known inconsistency with the usual Bazel convention where test code is only instrumented when `--instrument_test_targets` is set.

### `--instrument_test_targets`

By default, Bazel excludes test targets from instrumentation. If you want coverage of the test code itself (not just the libraries it exercises), add:

```text
coverage --instrument_test_targets
```

### Linking instrumented Rust into C/C++ targets

`rustc` links the LLVM profile runtime (`profiler_builtins`) into the binaries, `cdylib`s and `dylib`s it produces itself, but it does not bundle it into `staticlib` archives. A `rust_static_library` is linked by its C/C++ consumer, so the runtime that writes the Rust coverage data at process exit has to come from somewhere else.

When coverage is enabled and the archive contains instrumented Rust code (the `rust_static_library` itself or one of its direct Rust dependencies matches `--instrumentation_filter`), Rules Rust adds the Rust toolchain's own `profiler_builtins` archive to the `CcInfo` of the `rust_static_library`. This has two effects:

- The archive links even when the consuming `cc_*` target is built without coverage link flags (for example with `features = ["-coverage"]`), instead of failing on an undefined `__llvm_profile_runtime`.
- The runtime that reads the Rust coverage records is from the same LLVM version as the `rustc` that emitted them. The record layout is specific to an LLVM major version, so a runtime from a different LLVM, such as the one shipped with the consumer's C/C++ toolchain, can crash the process at exit.

The runtime is not added when nothing in the archive is instrumented, so a consumer that instruments only its C/C++ code keeps using its own toolchain's runtime. Bazel only reports instrumentation for direct dependencies, so a filter that instruments nothing but a deeper transitive crate is not detected and the consumer's runtime is used, as before.

Both compilers must still agree on the LLVM profile record layout if C/C++ and Rust coverage are mixed in one linked image. `rustc` tracks the current LLVM release while system compilers such as Apple clang often trail it by a major version or more. If they differ, restrict instrumentation to one language per linked image with `--instrumentation_filter`, or use a C/C++ toolchain built from the same LLVM major as `rustc`.

### Flags Summary

| Flag | Purpose |
|------|---------|
| `--instrumentation_filter=<regex>` | Controls which targets are instrumented. Default: `-/javatests[/:],-/test/java[/:]` |
| `--instrument_test_targets` | Also instrument test targets. Not required for library coverage via `rust_test` with `crate`. |
| `--combined_report=lcov` | Produce a combined LCOV report (set by default with `bazel coverage`). |
