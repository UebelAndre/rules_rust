"""Bazel infrastructure to automatically download the Android NDK.
"""

load("@apple_support//tools/http_dmg:http_dmg.bzl", "http_dmg")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@rules_android_ndk//:rules.bzl", "android_remote_ndk_repository")
load(":android_sdk_extensions.bzl", "ANDROID_PLATFORM_CONSTRAINTS")

_ANDROID_NDKS = {
    "r27d": {
        "darwin": {
            "integrity": "",
            "strip_prefix": "android-ndk-r27d",
            "urls": ["https://dl.google.com/android/repository/android-ndk-r27d-darwin.dmg"],
        },
        "linux": {
            "integrity": "",
            "strip_prefix": "android-ndk-r27d",
            "urls": ["https://dl.google.com/android/repository/android-ndk-r27d-linux.zip"],
        },
        "windows": {
            "integrity": "",
            "strip_prefix": "android-ndk-r27d",
            "urls": ["https://dl.google.com/android/repository/android-ndk-r27d-windows.zip"],
        },
    },
}

_TOOLCHAIN_TEMPLATE = """
toolchain(
    name = "{name}",
    exec_compatible_with = {exec_constraint_sets_serialized},
    target_compatible_with = {target_constraint_sets_serialized},
    target_settings = {target_settings_serialized},
    toolchain = "{toolchain}",
    toolchain_type = "{toolchain_type}",
    visibility = ["//visibility:public"],
)
"""

_CONSTRAINT_TEMPLATE = """
config_setting(
    name = "darwin",
    constraint_values = ["@platforms//os:macos"],
    visibility = ["//visibility:public"],
)

config_setting(
    name = "linux",
    constraint_values = ["@platforms//os:linux"],
    visibility = ["//visibility:public"],
)

config_setting(
    name = "windows",
    constraint_values = ["@platforms//os:windows"],
    visibility = ["//visibility:public"],
)
"""

_ALIASES_TEMPLATE = """
alias(
    name = "cpufeatures",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:cpufeatures",
        "@platforms//os:linux": "@{linux}//:cpufeatures",
        "@platforms//os:windows": "@{windows}//:cpufeatures",
    }}),
    visibility = ["//visibility:public"],
)

alias(
    name = "native_app_glue",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:native_app_glue",
        "@platforms//os:linux": "@{linux}//:native_app_glue",
        "@platforms//os:windows": "@{windows}//:native_app_glue",
    }}),
    visibility = ["//visibility:public"],
)
"""

def BUILD_for_toolchain_hub(
        toolchain_names,
        toolchain_labels,
        toolchain_types,
        target_settings,
        target_compatible_with,
        exec_compatible_with,
        ndk_repositories):
    """Generate BUILD file for the toolchain hub.

    Args:
        toolchain_names: List of toolchain names
        toolchain_labels: Dict of toolchain labels
        toolchain_types: Dict of toolchain types
        target_settings: Dict of target settings
        target_compatible_with: Dict of target compatible constraints
        exec_compatible_with: Dict of exec compatible constraints
        ndk_repositories: Dict mapping platform -> repository name for creating aliases

    Returns:
        BUILD file content as string
    """

    contents = []

    contents.append(_CONSTRAINT_TEMPLATE)

    contents.extend([_TOOLCHAIN_TEMPLATE.format(
        name = toolchain_name,
        exec_constraint_sets_serialized = json.encode(exec_compatible_with[toolchain_name]),
        target_constraint_sets_serialized = json.encode(target_compatible_with[toolchain_name]),
        target_settings_serialized = json.encode(target_settings[toolchain_name]) if toolchain_name in target_settings else "None",
        toolchain = toolchain_labels[toolchain_name],
        toolchain_type = toolchain_types[toolchain_name],
    ) for toolchain_name in toolchain_names])

    contents.append(_ALIASES_TEMPLATE.format(
        darwin = ndk_repositories["darwin"],
        linux = ndk_repositories["linux"],
        windows = ndk_repositories["windows"],
    ))

    return "\n".join(contents)

def _toolchain_repository_hub_impl(repository_ctx):
    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")""".format(
        repository_ctx.name,
    ))

    repository_ctx.file("BUILD.bazel", BUILD_for_toolchain_hub(
        toolchain_names = repository_ctx.attr.toolchain_names,
        toolchain_labels = repository_ctx.attr.toolchain_labels,
        toolchain_types = repository_ctx.attr.toolchain_types,
        target_settings = repository_ctx.attr.target_settings,
        target_compatible_with = repository_ctx.attr.target_compatible_with,
        exec_compatible_with = repository_ctx.attr.exec_compatible_with,
        ndk_repositories = repository_ctx.attr.ndk_repositories,
    ))

_toolchain_repository_hub = repository_rule(
    doc = (
        "Generates a toolchain-bearing repository that declares a set of other toolchains from other " +
        "repositories. This exists to allow registering a set of toolchains in one go with the `:all` target."
    ),
    attrs = {
        "exec_compatible_with": attr.string_list_dict(
            doc = "A list of constraints for the execution platform for this toolchain, keyed by toolchain name.",
            mandatory = True,
        ),
        "ndk_repositories": attr.string_dict(
            doc = "Mapping of platform names to NDK repository names for creating aliases.",
            mandatory = True,
        ),
        "target_compatible_with": attr.string_list_dict(
            doc = "A list of constraints for the target platform for this toolchain, keyed by toolchain name.",
            mandatory = True,
        ),
        "target_settings": attr.string_list_dict(
            doc = "A list of config_settings that must be satisfied by the target configuration in order for this toolchain to be selected during toolchain resolution.",
            mandatory = True,
        ),
        "toolchain_labels": attr.string_dict(
            doc = "The name of the toolchain implementation target, keyed by toolchain name.",
            mandatory = True,
        ),
        "toolchain_names": attr.string_list(
            mandatory = True,
        ),
        "toolchain_types": attr.string_dict(
            doc = "The toolchain type of the toolchain to declare, keyed by toolchain name.",
            mandatory = True,
        ),
    },
    implementation = _toolchain_repository_hub_impl,
)

def _android_ndk_extension_impl(module_ctx):
    version = "r27d"

    platforms = _ANDROID_NDKS[version]

    # Build the toolchain repository hub parameters
    toolchain_names = []
    toolchain_labels = {}
    toolchain_types = {}
    exec_compatible_with = {}
    target_compatible_with = {}
    target_settings = {}
    ndk_repositories = {}

    for platform, info in platforms.items():
        plat_name = "androidndk_{}_{}".format(version, platform)
        files_name = "{}_files".format(plat_name)
        http_rule = http_archive
        if platform == "darwin":
            http_rule = http_dmg

        http_rule(
            name = files_name,
            urls = info["urls"],
            strip_prefix = info["strip_prefix"],
            build_file_content = """exports_files(glob(["**/*"], visibility = ["//visibility:public"]))\n""",
            integrity = info["integrity"],
        )

        android_remote_ndk_repository(
            name = plat_name,
            anchor = str(Label("@{}//:BUILD.bazel".format(files_name))),
            api_level = 21,
            platform = platform,
            clang_resource_dir = "IDK",
        )

        plat_name = "androidndk_{}_{}".format(version, platform)
        toolchain_name = "ndk_{}".format(platform)
        toolchain_names.append(toolchain_name)

        toolchain_labels[toolchain_name] = "@{}//toolchains:all".format(plat_name)
        toolchain_types[toolchain_name] = "@bazel_tools//tools/cpp:toolchain_type"
        exec_compatible_with[toolchain_name] = ANDROID_PLATFORM_CONSTRAINTS[platform]
        target_compatible_with[toolchain_name] = ["@platforms//os:android"]

        # Store repository name for creating aliases
        ndk_repositories[platform] = plat_name

    _toolchain_repository_hub(
        name = "androidndk",
        toolchain_names = toolchain_names,
        toolchain_labels = toolchain_labels,
        toolchain_types = toolchain_types,
        exec_compatible_with = exec_compatible_with,
        target_compatible_with = target_compatible_with,
        target_settings = target_settings,
        ndk_repositories = ndk_repositories,
    )

    return module_ctx.extension_metadata(
        reproducible = True,
        root_module_direct_deps = ["androidndk"] + ndk_repositories.values(),
        root_module_direct_dev_deps = [],
    )

android_ndk = module_extension(
    doc = "Downloads Android NDK. Workaround for https://github.com/bazelbuild/rules_android_ndk/issues/44",
    implementation = _android_ndk_extension_impl,
)
