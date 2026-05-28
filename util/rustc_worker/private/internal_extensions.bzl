"""Bzlmod module extensions for rustc_worker internal dependencies"""

load("@bazel_features//:features.bzl", "bazel_features")
load("//util/rustc_worker/3rdparty/crates:crates.bzl", "crate_repositories")

def _internal_deps_impl(module_ctx):
    direct_deps = []
    direct_deps.extend(crate_repositories())

    metadata_kwargs = {
        "root_module_direct_deps": [repo.repo for repo in direct_deps],
        "root_module_direct_dev_deps": [],
    }

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        metadata_kwargs["reproducible"] = True

    return module_ctx.extension_metadata(**metadata_kwargs)

# Short name to reduce path lengths on Windows.
i = module_extension(
    doc = "Dependencies for rustc_worker",
    implementation = _internal_deps_impl,
)
