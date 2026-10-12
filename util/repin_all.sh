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

for d in extensions/* examples/hello_world examples/sys examples/all_deps_vendor examples/ios_build; do
  pushd "${d}"
  for target in $(bazel query 'kind("crates_vendor", //...)'); do
    bazel run "${target}"
  done
  popd
done

# Vendor consolidated workspace. Locally vendored crate sources are not checked
# in, so their packages fail to load until the vendor targets have run; `--keep_going`
# still lists the vendor targets themselves.
(cd crate_universe/tests/integration/vendor && \
  for target in $(bazel query --keep_going 'kind("crates_vendor", //...)' 2>/dev/null || true); do
    CARGO_BAZEL_REPIN=true bazel run "${target}"
  done
)

for d in crate_universe/tests/integration/* examples/cross_compile_musl
do
  # vendor/ is handled explicitly above via bazel run of crates_vendor targets
  [[ "${d}" == */vendor ]] && continue
  # Analyze rather than `bazel query //...`: a plain package query only evaluates
  # `load()` statements, so a workspace whose BUILD files reach the crate repository
  # purely through labels would never fetch it and would silently not be repinned.
  (cd "${d}" && CARGO_BAZEL_REPIN=true bazel build --nobuild //...)
done

# `nix_cross_compiling` special cased as `//...` will invoke Nix.
(cd examples/cross_compile_nix && CARGO_BAZEL_REPIN=true bazel query @crate_index//... >/dev/null)
