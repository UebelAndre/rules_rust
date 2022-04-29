"""Module extensions for rules_rust/bindgen."""

load("//bindgen:repositories.bzl", "rust_bindgen_repositories")

def _toolchains_impl(_ctx):
    rust_bindgen_repositories()

toolchains = module_extension(implementation = _toolchains_impl)
