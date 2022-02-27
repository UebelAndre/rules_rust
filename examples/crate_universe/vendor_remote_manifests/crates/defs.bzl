###############################################################################
# @generated
# This file is auto-generated by the cargo-bazel tool.
#
# DO NOT MODIFY: Local changes may be replaced in future executions.
###############################################################################
"""
# `crates_repository` API

- [aliases](#aliases)
- [crate_deps](#crate_deps)
- [all_crate_deps](#all_crate_deps)
- [crate_repositories](#crate_repositories)

"""

load("@bazel_skylib//lib:selects.bzl", "selects")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

###############################################################################
# MACROS API
###############################################################################

# An identifier that represent common dependencies (unconditional).
_COMMON_CONDITION = ""

def _flatten_dependency_maps(all_dependency_maps):
    """Flatten a list of dependency maps into one dictionary.

    Dependency maps have the following structure:

    ```python
    DEPENDENCIES_MAP = {
        # The first key in the map is a Bazel package
        # name of the workspace this file is defined in.
        "workspace_member_package": {

            # Not all dependnecies are supported for all platforms.
            # the condition key is the condition required to be true
            # on the host platform.
            "condition": {

                # An alias to a crate target.     # The label of the crate target the
                # Aliases are only crate names.   # package name refers to.
                "package_name":                   "@full//:label",
            }
        }
    }
    ```

    Args:
        all_dependency_maps (list): A list of dicts as described above

    Returns:
        dict: A dictionary as described above
    """
    dependencies = {}

    for workspace_deps_map in all_dependency_maps:
        for pkg_name, conditional_deps_map in workspace_deps_map.items():
            if pkg_name not in dependencies:
                non_frozen_map = dict()
                for key, values in conditional_deps_map.items():
                    non_frozen_map.update({key: dict(values.items())})
                dependencies.setdefault(pkg_name, non_frozen_map)
                continue

            for condition, deps_map in conditional_deps_map.items():
                # If the condition has not been recorded, do so and continue
                if condition not in dependencies[pkg_name]:
                    dependencies[pkg_name].setdefault(condition, dict(deps_map.items()))
                    continue

                # Alert on any miss-matched dependencies
                inconsistent_entries = []
                for crate_name, crate_label in deps_map.items():
                    existing = dependencies[pkg_name][condition].get(crate_name)
                    if existing and existing != crate_label:
                        inconsistent_entries.append((crate_name, existing, crate_label))
                    dependencies[pkg_name][condition].update({crate_name: crate_label})

    return dependencies

def crate_deps(deps, package_name = None):
    """Finds the fully qualified label of the requested crates for the package where this macro is called.

    Args:
        deps (list): The desired list of crate targets.
        package_name (str, optional): The package name of the set of dependencies to look up.
            Defaults to `native.package_name()`.

    Returns:
        list: A list of labels to generated rust targets (str)
    """

    if not deps:
        return []

    if package_name == None:
        package_name = native.package_name()

    # Join both sets of dependencies
    dependencies = _flatten_dependency_maps([
        _NORMAL_DEPENDENCIES,
        _NORMAL_DEV_DEPENDENCIES,
        _PROC_MACRO_DEPENDENCIES,
        _PROC_MACRO_DEV_DEPENDENCIES,
        _BUILD_DEPENDENCIES,
        _BUILD_PROC_MACRO_DEPENDENCIES,
    ]).pop(package_name, {})

    # Combine all conditional packages so we can easily index over a flat list
    # TODO: Perhaps this should actually return select statements and maintain
    # the conditionals of the dependencies
    flat_deps = {}
    for deps_set in dependencies.values():
        for crate_name, crate_label in deps_set.items():
            flat_deps.update({crate_name: crate_label})

    missing_crates = []
    crate_targets = []
    for crate_target in deps:
        if crate_target not in flat_deps:
            missing_crates.append(crate_target)
        else:
            crate_targets.append(flat_deps[crate_target])

    if missing_crates:
        fail("Could not find crates `{}` among dependencies of `{}`. Available dependencies were `{}`".format(
            missing_crates,
            package_name,
            dependencies,
        ))

    return crate_targets

def all_crate_deps(
        normal = False,
        normal_dev = False,
        proc_macro = False,
        proc_macro_dev = False,
        build = False,
        build_proc_macro = False,
        package_name = None):
    """Finds the fully qualified label of all requested direct crate dependencies \
    for the package where this macro is called.

    If no parameters are set, all normal dependencies are returned. Setting any one flag will
    otherwise impact the contents of the returned list.

    Args:
        normal (bool, optional): If True, normal dependencies are included in the
            output list.
        normal_dev (bool, optional): If True, normla dev dependencies will be
            included in the output list..
        proc_macro (bool, optional): If True, proc_macro dependencies are included
            in the output list.
        proc_macro_dev (bool, optional): If True, dev proc_macro dependencies are
            included in the output list.
        build (bool, optional): If True, build dependencies are included
            in the output list.
        build_proc_macro (bool, optional): If True, build proc_macro dependencies are
            included in the output list.
        package_name (str, optional): The package name of the set of dependencies to look up.
            Defaults to `native.package_name()` when unset.

    Returns:
        list: A list of labels to generated rust targets (str)
    """

    if package_name == None:
        package_name = native.package_name()

    # Determine the relevant maps to use
    all_dependency_maps = []
    if normal:
        all_dependency_maps.append(_NORMAL_DEPENDENCIES)
    if normal_dev:
        all_dependency_maps.append(_NORMAL_DEV_DEPENDENCIES)
    if proc_macro:
        all_dependency_maps.append(_PROC_MACRO_DEPENDENCIES)
    if proc_macro_dev:
        all_dependency_maps.append(_PROC_MACRO_DEV_DEPENDENCIES)
    if build:
        all_dependency_maps.append(_BUILD_DEPENDENCIES)
    if build_proc_macro:
        all_dependency_maps.append(_BUILD_PROC_MACRO_DEPENDENCIES)

    # Default to always using normal dependencies
    if not all_dependency_maps:
        all_dependency_maps.append(_NORMAL_DEPENDENCIES)

    dependencies = _flatten_dependency_maps(all_dependency_maps).pop(package_name, None)

    if not dependencies:
        return []

    crate_deps = list(dependencies.pop(_COMMON_CONDITION, {}).values())
    for condition, deps in dependencies.items():
        crate_deps += selects.with_or({_CONDITIONS[condition]: deps.values()})

    return crate_deps

def aliases(
        normal = False,
        normal_dev = False,
        proc_macro = False,
        proc_macro_dev = False,
        build = False,
        build_proc_macro = False,
        package_name = None):
    """Produces a map of Crate alias names to their original label

    If no dependency kinds are specified, `normal` and `proc_macro` are used by default.
    Setting any one flag will otherwise determine the contents of the returned dict.

    Args:
        normal (bool, optional): If True, normal dependencies are included in the
            output list.
        normal_dev (bool, optional): If True, normla dev dependencies will be
            included in the output list..
        proc_macro (bool, optional): If True, proc_macro dependencies are included
            in the output list.
        proc_macro_dev (bool, optional): If True, dev proc_macro dependencies are
            included in the output list.
        build (bool, optional): If True, build dependencies are included
            in the output list.
        build_proc_macro (bool, optional): If True, build proc_macro dependencies are
            included in the output list.
        package_name (str, optional): The package name of the set of dependencies to look up.
            Defaults to `native.package_name()` when unset.

    Returns:
        dict: The aliases of all associated packages
    """
    if package_name == None:
        package_name = native.package_name()

    # Determine the relevant maps to use
    all_aliases_maps = []
    if normal:
        all_aliases_maps.append(_NORMAL_ALIASES)
    if normal_dev:
        all_aliases_maps.append(_NORMAL_DEV_ALIASES)
    if proc_macro:
        all_aliases_maps.append(_PROC_MACRO_ALIASES)
    if proc_macro_dev:
        all_aliases_maps.append(_PROC_MACRO_DEV_ALIASES)
    if build:
        all_aliases_maps.append(_BUILD_ALIASES)
    if build_proc_macro:
        all_aliases_maps.append(_BUILD_PROC_MACRO_ALIASES)

    # Default to always using normal aliases
    if not all_aliases_maps:
        all_aliases_maps.append(_NORMAL_ALIASES)
        all_aliases_maps.append(_PROC_MACRO_ALIASES)

    aliases = _flatten_dependency_maps(all_aliases_maps).pop(package_name, None)

    if not aliases:
        return dict()

    common_items = aliases.pop(_COMMON_CONDITION, {}).items()

    # If there are only common items in the dictionary, immediately return them
    if not len(aliases.keys()) == 1:
        return dict(common_items)

    # Build a single select statement where each conditional has accounted for the
    # common set of aliases.
    crate_aliases = {"//conditions:default": common_items}
    for condition, deps in aliases.items():
        condition_triples = _CONDITIONS[condition]
        if condition_triples in crate_aliases:
            crate_aliases[condition_triples].update(deps)
        else:
            crate_aliases.update({_CONDITIONS[condition]: dict(deps.items() + common_items)})

    return selects.with_or(crate_aliases)

###############################################################################
# WORKSPACE MEMBER DEPS AND ALIASES
###############################################################################

_NORMAL_DEPENDENCIES = {
    "vendor_remote_manifests": {
        _COMMON_CONDITION: {
            "tokio": "@crates_vendor_manifests__tokio-1.16.1//:tokio",
        },
    },
}

_NORMAL_ALIASES = {
    "vendor_remote_manifests": {
        _COMMON_CONDITION: {
        },
    },
}

_NORMAL_DEV_DEPENDENCIES = {
    "vendor_remote_manifests": {
        _COMMON_CONDITION: {
            "tempfile": "@crates_vendor_manifests__tempfile-3.3.0//:tempfile",
            "tokio-test": "@crates_vendor_manifests__tokio-test-0.4.2//:tokio_test",
        },
    },
}

_NORMAL_DEV_ALIASES = {
    "vendor_remote_manifests": {
        _COMMON_CONDITION: {
        },
    },
}

_PROC_MACRO_DEPENDENCIES = {
    "vendor_remote_manifests": {
    },
}

_PROC_MACRO_ALIASES = {
    "vendor_remote_manifests": {
    },
}

_PROC_MACRO_DEV_DEPENDENCIES = {
    "vendor_remote_manifests": {
    },
}

_PROC_MACRO_DEV_ALIASES = {
    "vendor_remote_manifests": {
        _COMMON_CONDITION: {
        },
    },
}

_BUILD_DEPENDENCIES = {
    "vendor_remote_manifests": {
    },
}

_BUILD_ALIASES = {
    "vendor_remote_manifests": {
    },
}

_BUILD_PROC_MACRO_DEPENDENCIES = {
    "vendor_remote_manifests": {
    },
}

_BUILD_PROC_MACRO_ALIASES = {
    "vendor_remote_manifests": {
    },
}

_CONDITIONS = {
    "cfg(all(any(target_arch = \"x86_64\", target_arch = \"aarch64\"), target_os = \"hermit\"))": [],
    "cfg(any(unix, target_os = \"wasi\"))": ["aarch64-apple-darwin", "aarch64-apple-ios", "aarch64-linux-android", "aarch64-unknown-linux-gnu", "arm-unknown-linux-gnueabi", "armv7-unknown-linux-gnueabi", "i686-apple-darwin", "i686-linux-android", "i686-unknown-freebsd", "i686-unknown-linux-gnu", "powerpc-unknown-linux-gnu", "s390x-unknown-linux-gnu", "wasm32-wasi", "x86_64-apple-darwin", "x86_64-apple-ios", "x86_64-linux-android", "x86_64-unknown-freebsd", "x86_64-unknown-linux-gnu"],
    "cfg(not(windows))": ["aarch64-apple-darwin", "aarch64-apple-ios", "aarch64-linux-android", "aarch64-unknown-linux-gnu", "arm-unknown-linux-gnueabi", "armv7-unknown-linux-gnueabi", "i686-apple-darwin", "i686-linux-android", "i686-unknown-freebsd", "i686-unknown-linux-gnu", "powerpc-unknown-linux-gnu", "s390x-unknown-linux-gnu", "wasm32-unknown-unknown", "wasm32-wasi", "x86_64-apple-darwin", "x86_64-apple-ios", "x86_64-linux-android", "x86_64-unknown-freebsd", "x86_64-unknown-linux-gnu"],
    "cfg(target = \"i686-pc-windows-gnu\")": [],
    "cfg(target = \"x86_64-pc-windows-gnu\")": [],
    "cfg(target_arch = \"wasm32\")": ["wasm32-unknown-unknown", "wasm32-wasi"],
    "cfg(target_os = \"redox\")": [],
    "cfg(unix)": ["aarch64-apple-darwin", "aarch64-apple-ios", "aarch64-linux-android", "aarch64-unknown-linux-gnu", "arm-unknown-linux-gnueabi", "armv7-unknown-linux-gnueabi", "i686-apple-darwin", "i686-linux-android", "i686-unknown-freebsd", "i686-unknown-linux-gnu", "powerpc-unknown-linux-gnu", "s390x-unknown-linux-gnu", "x86_64-apple-darwin", "x86_64-apple-ios", "x86_64-linux-android", "x86_64-unknown-freebsd", "x86_64-unknown-linux-gnu"],
    "cfg(windows)": ["i686-pc-windows-msvc", "x86_64-pc-windows-msvc"],
}

###############################################################################

def crate_repositories():
    """A macro for defining repositories for all generated crates"""
    maybe(
        http_archive,
        name = "crates_vendor_manifests__async-stream-0.3.2",
        sha256 = "171374e7e3b2504e0e5236e3b59260560f9fe94bfe9ac39ba5e4e929c5590625",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/async-stream/0.3.2/download"],
        strip_prefix = "async-stream-0.3.2",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.async-stream-0.3.2.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__async-stream-impl-0.3.2",
        sha256 = "648ed8c8d2ce5409ccd57453d9d1b214b342a0d69376a6feda1fd6cae3299308",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/async-stream-impl/0.3.2/download"],
        strip_prefix = "async-stream-impl-0.3.2",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.async-stream-impl-0.3.2.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__bitflags-1.3.2",
        sha256 = "bef38d45163c2f1dde094a7dfd33ccf595c92905c8f8f4fdc18d06fb1037718a",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/bitflags/1.3.2/download"],
        strip_prefix = "bitflags-1.3.2",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.bitflags-1.3.2.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__bytes-1.1.0",
        sha256 = "c4872d67bab6358e59559027aa3b9157c53d9358c51423c17554809a8858e0f8",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/bytes/1.1.0/download"],
        strip_prefix = "bytes-1.1.0",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.bytes-1.1.0.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__cfg-if-1.0.0",
        sha256 = "baf1de4339761588bc0619e3cbc0120ee582ebb74b53b4efbf79117bd2da40fd",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/cfg-if/1.0.0/download"],
        strip_prefix = "cfg-if-1.0.0",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.cfg-if-1.0.0.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__fastrand-1.7.0",
        sha256 = "c3fcf0cee53519c866c09b5de1f6c56ff9d647101f81c1964fa632e148896cdf",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/fastrand/1.7.0/download"],
        strip_prefix = "fastrand-1.7.0",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.fastrand-1.7.0.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__futures-core-0.3.21",
        sha256 = "0c09fd04b7e4073ac7156a9539b57a484a8ea920f79c7c675d05d289ab6110d3",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/futures-core/0.3.21/download"],
        strip_prefix = "futures-core-0.3.21",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.futures-core-0.3.21.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__hermit-abi-0.1.19",
        sha256 = "62b467343b94ba476dcb2500d242dadbb39557df889310ac77c5d99100aaac33",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/hermit-abi/0.1.19/download"],
        strip_prefix = "hermit-abi-0.1.19",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.hermit-abi-0.1.19.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__instant-0.1.12",
        sha256 = "7a5bbe824c507c5da5956355e86a746d82e0e1464f65d862cc5e71da70e94b2c",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/instant/0.1.12/download"],
        strip_prefix = "instant-0.1.12",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.instant-0.1.12.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__libc-0.2.119",
        sha256 = "1bf2e165bb3457c8e098ea76f3e3bc9db55f87aa90d52d0e6be741470916aaa4",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/libc/0.2.119/download"],
        strip_prefix = "libc-0.2.119",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.libc-0.2.119.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__lock_api-0.4.6",
        sha256 = "88943dd7ef4a2e5a4bfa2753aaab3013e34ce2533d1996fb18ef591e315e2b3b",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/lock_api/0.4.6/download"],
        strip_prefix = "lock_api-0.4.6",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.lock_api-0.4.6.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__log-0.4.14",
        sha256 = "51b9bbe6c47d51fc3e1a9b945965946b4c44142ab8792c50835a980d362c2710",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/log/0.4.14/download"],
        strip_prefix = "log-0.4.14",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.log-0.4.14.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__memchr-2.4.1",
        sha256 = "308cc39be01b73d0d18f82a0e7b2a3df85245f84af96fdddc5d202d27e47b86a",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/memchr/2.4.1/download"],
        strip_prefix = "memchr-2.4.1",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.memchr-2.4.1.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__mio-0.7.14",
        sha256 = "8067b404fe97c70829f082dec8bcf4f71225d7eaea1d8645349cb76fa06205cc",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/mio/0.7.14/download"],
        strip_prefix = "mio-0.7.14",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.mio-0.7.14.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__miow-0.3.7",
        sha256 = "b9f1c5b025cda876f66ef43a113f91ebc9f4ccef34843000e0adf6ebbab84e21",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/miow/0.3.7/download"],
        strip_prefix = "miow-0.3.7",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.miow-0.3.7.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__ntapi-0.3.7",
        sha256 = "c28774a7fd2fbb4f0babd8237ce554b73af68021b5f695a3cebd6c59bac0980f",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/ntapi/0.3.7/download"],
        strip_prefix = "ntapi-0.3.7",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.ntapi-0.3.7.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__num_cpus-1.13.1",
        sha256 = "19e64526ebdee182341572e50e9ad03965aa510cd94427a4549448f285e957a1",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/num_cpus/1.13.1/download"],
        strip_prefix = "num_cpus-1.13.1",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.num_cpus-1.13.1.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__once_cell-1.9.0",
        sha256 = "da32515d9f6e6e489d7bc9d84c71b060db7247dc035bbe44eac88cf87486d8d5",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/once_cell/1.9.0/download"],
        strip_prefix = "once_cell-1.9.0",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.once_cell-1.9.0.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__parking_lot-0.11.2",
        sha256 = "7d17b78036a60663b797adeaee46f5c9dfebb86948d1255007a1d6be0271ff99",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/parking_lot/0.11.2/download"],
        strip_prefix = "parking_lot-0.11.2",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.parking_lot-0.11.2.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__parking_lot_core-0.8.5",
        sha256 = "d76e8e1493bcac0d2766c42737f34458f1c8c50c0d23bcb24ea953affb273216",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/parking_lot_core/0.8.5/download"],
        strip_prefix = "parking_lot_core-0.8.5",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.parking_lot_core-0.8.5.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__pin-project-lite-0.2.8",
        sha256 = "e280fbe77cc62c91527259e9442153f4688736748d24660126286329742b4c6c",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/pin-project-lite/0.2.8/download"],
        strip_prefix = "pin-project-lite-0.2.8",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.pin-project-lite-0.2.8.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__proc-macro2-1.0.36",
        sha256 = "c7342d5883fbccae1cc37a2353b09c87c9b0f3afd73f5fb9bba687a1f733b029",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/proc-macro2/1.0.36/download"],
        strip_prefix = "proc-macro2-1.0.36",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.proc-macro2-1.0.36.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__quote-1.0.15",
        sha256 = "864d3e96a899863136fc6e99f3d7cae289dafe43bf2c5ac19b70df7210c0a145",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/quote/1.0.15/download"],
        strip_prefix = "quote-1.0.15",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.quote-1.0.15.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__redox_syscall-0.2.10",
        sha256 = "8383f39639269cde97d255a32bdb68c047337295414940c68bdd30c2e13203ff",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/redox_syscall/0.2.10/download"],
        strip_prefix = "redox_syscall-0.2.10",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.redox_syscall-0.2.10.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__remove_dir_all-0.5.3",
        sha256 = "3acd125665422973a33ac9d3dd2df85edad0f4ae9b00dafb1a05e43a9f5ef8e7",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/remove_dir_all/0.5.3/download"],
        strip_prefix = "remove_dir_all-0.5.3",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.remove_dir_all-0.5.3.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__scopeguard-1.1.0",
        sha256 = "d29ab0c6d3fc0ee92fe66e2d99f700eab17a8d57d1c1d3b748380fb20baa78cd",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/scopeguard/1.1.0/download"],
        strip_prefix = "scopeguard-1.1.0",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.scopeguard-1.1.0.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__signal-hook-registry-1.4.0",
        sha256 = "e51e73328dc4ac0c7ccbda3a494dfa03df1de2f46018127f60c693f2648455b0",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/signal-hook-registry/1.4.0/download"],
        strip_prefix = "signal-hook-registry-1.4.0",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.signal-hook-registry-1.4.0.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__smallvec-1.8.0",
        sha256 = "f2dd574626839106c320a323308629dcb1acfc96e32a8cba364ddc61ac23ee83",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/smallvec/1.8.0/download"],
        strip_prefix = "smallvec-1.8.0",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.smallvec-1.8.0.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__syn-1.0.86",
        sha256 = "8a65b3f4ffa0092e9887669db0eae07941f023991ab58ea44da8fe8e2d511c6b",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/syn/1.0.86/download"],
        strip_prefix = "syn-1.0.86",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.syn-1.0.86.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__tempfile-3.3.0",
        sha256 = "5cdb1ef4eaeeaddc8fbd371e5017057064af0911902ef36b39801f67cc6d79e4",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/tempfile/3.3.0/download"],
        strip_prefix = "tempfile-3.3.0",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.tempfile-3.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__tokio-1.16.1",
        sha256 = "0c27a64b625de6d309e8c57716ba93021dccf1b3b5c97edd6d3dd2d2135afc0a",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/tokio/1.16.1/download"],
        strip_prefix = "tokio-1.16.1",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.tokio-1.16.1.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__tokio-macros-1.7.0",
        sha256 = "b557f72f448c511a979e2564e55d74e6c4432fc96ff4f6241bc6bded342643b7",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/tokio-macros/1.7.0/download"],
        strip_prefix = "tokio-macros-1.7.0",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.tokio-macros-1.7.0.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__tokio-stream-0.1.8",
        sha256 = "50145484efff8818b5ccd256697f36863f587da82cf8b409c53adf1e840798e3",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/tokio-stream/0.1.8/download"],
        strip_prefix = "tokio-stream-0.1.8",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.tokio-stream-0.1.8.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__tokio-test-0.4.2",
        sha256 = "53474327ae5e166530d17f2d956afcb4f8a004de581b3cae10f12006bc8163e3",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/tokio-test/0.4.2/download"],
        strip_prefix = "tokio-test-0.4.2",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.tokio-test-0.4.2.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__unicode-xid-0.2.2",
        sha256 = "8ccb82d61f80a663efe1f787a51b16b5a51e3314d6ac365b08639f52387b33f3",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/unicode-xid/0.2.2/download"],
        strip_prefix = "unicode-xid-0.2.2",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.unicode-xid-0.2.2.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__winapi-0.3.9",
        sha256 = "5c839a674fcd7a98952e593242ea400abe93992746761e38641405d28b00f419",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/winapi/0.3.9/download"],
        strip_prefix = "winapi-0.3.9",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.winapi-0.3.9.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__winapi-i686-pc-windows-gnu-0.4.0",
        sha256 = "ac3b87c63620426dd9b991e5ce0329eff545bccbbb34f3be09ff6fb6ab51b7b6",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/winapi-i686-pc-windows-gnu/0.4.0/download"],
        strip_prefix = "winapi-i686-pc-windows-gnu-0.4.0",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.winapi-i686-pc-windows-gnu-0.4.0.bazel"),
    )

    maybe(
        http_archive,
        name = "crates_vendor_manifests__winapi-x86_64-pc-windows-gnu-0.4.0",
        sha256 = "712e227841d057c1ee1cd2fb22fa7e5a5461ae8e48fa2ca79ec42cfc1931183f",
        type = "tar.gz",
        urls = ["https://crates.io/api/v1/crates/winapi-x86_64-pc-windows-gnu/0.4.0/download"],
        strip_prefix = "winapi-x86_64-pc-windows-gnu-0.4.0",
        build_file = Label("@examples//vendor_remote_manifests/crates:BUILD.winapi-x86_64-pc-windows-gnu-0.4.0.bazel"),
    )
