#!/usr/bin/env bash
set -xeuo pipefail

# Normalize working directory to root of repository.
cd "$(dirname "${BASH_SOURCE[0]}")"/..

# Build the cargo-bazel binary and expose it for repin operations.
bazel build -c opt //crate_universe:cargo_bazel_bin
CARGO_BAZEL_GENERATOR="$(pwd)/$(bazel cquery -c opt --output=files //crate_universe:cargo_bazel_bin 2>/dev/null)"
CARGO_BAZEL_GENERATOR_URL="file://${CARGO_BAZEL_GENERATOR}"
export CARGO_BAZEL_GENERATOR_URL

# Bazel caches downloads by URL, so without a checksum a rebuilt binary at the
# same path would be served from the cache of an earlier run.
if command -v sha256sum >/dev/null 2>&1; then
  CARGO_BAZEL_GENERATOR_SHA256="$(sha256sum "${CARGO_BAZEL_GENERATOR}" | cut -d' ' -f1)"
else
  CARGO_BAZEL_GENERATOR_SHA256="$(shasum -a 256 "${CARGO_BAZEL_GENERATOR}" | cut -d' ' -f1)"
fi
export CARGO_BAZEL_GENERATOR_SHA256

# Re-generates all files which may need to be re-generated after changing crate_universe.
for target in $(bazel query 'kind("crates_vendor", //...)'); do
  bazel run "${target}"
done

for d in examples/hello_world examples/sys examples/all_deps_vendor examples/ios_build; do
  pushd "${d}"
  for target in $(bazel query 'kind("crates_vendor", //...)'); do
    bazel run "${target}"
  done
  popd
done

# The extensions declare their crates with the `crate` module extension; querying
# a hub evaluates the extension, which repins its lockfiles.
for pair in bindgen:rules_rust_bindgen_deps mdbook:rmdbi prost:rrprd pyo3:rpyo3c wasm_bindgen:rrwbd; do
  (cd "extensions/${pair%%:*}" && CARGO_BAZEL_REPIN=true bazel query "@${pair#*:}//..." >/dev/null)
done

# Vendor consolidated workspace. Locally vendored crate sources are not checked
# in, so their packages fail to load until the vendor targets have run; `--keep_going`
# still lists the vendor targets themselves.
(cd crate_universe/tests/integration/vendor && \
  for target in $(bazel query --keep_going 'kind("crates_vendor", //...)' 2>/dev/null || true); do
    CARGO_BAZEL_REPIN=true bazel run "${target}"
  done
)

# Repinning happens when the `crate` module extension (or repository rule) is
# evaluated. Querying `//...` alone only loads the root module's BUILD files,
# which is not enough for workspaces that reference their crate repositories
# purely as `deps` labels (e.g. `@crates//:foo`) without `load()`ing from them.
# Querying the direct dependencies of `//...` forces the packages of those
# repositories to load, which evaluates the extension and triggers the repin,
# without descending into (and downloading) every transitive crate source.
for d in crate_universe/tests/integration/* examples/cross_compile_musl
do
  # vendor/ is handled explicitly above via bazel run of crates_vendor targets
  [[ "${d}" == */vendor ]] && continue
  (cd "${d}" && CARGO_BAZEL_REPIN=true bazel query 'deps(//..., 1)' >/dev/null)
done

# `nix_cross_compiling` special cased as `//...` will invoke Nix.
(cd examples/cross_compile_nix && CARGO_BAZEL_REPIN=true bazel query @crate_index//... >/dev/null)
