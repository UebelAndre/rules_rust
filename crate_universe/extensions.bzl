"""Module extensions for rules_rust/crate_universe."""

load("//crate_universe:repositories.bzl", "crate_universe_dependencies")

def _dependencies_impl(_ctx):
    crate_universe_dependencies()

dependencies = module_extension(implementation = _dependencies_impl)
