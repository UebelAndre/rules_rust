"""Module extensions for rules_rust."""

load("//rust:repositories.bzl", "rust_register_toolchains")

def _toolchains_impl(_ctx):
    rust_register_toolchains()

toolchains = module_extension(implementation = _toolchains_impl)
