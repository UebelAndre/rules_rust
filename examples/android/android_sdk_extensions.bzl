"""Bazel infrastructure to automatically download the Android SDK.
"""

load("@rules_android//rules/android_sdk_repository:rule.bzl", "android_sdk_repository")

# Android SDK component URLs extracted from sdk.log
# These are the core components needed for building Android apps
_ANDROID_SDK_COMPONENTS = {
    "36": {
        "darwin": {
            "build_tools": {
                "integrity": "",
                "urls": ["https://dl.google.com/android/repository/build-tools_r36.1_macosx.zip"],
            },
            "emulator": {
                "integrity": "",
                "urls": ["https://dl.google.com/android/repository/emulator-darwin_aarch64-14214601.zip"],
            },
            "platform": {
                "integrity": "",
                "strip_prefix": "android-14",
                "urls": ["https://dl.google.com/android/repository/platform-36_r02.zip"],
            },
            "platform_tools": {
                "integrity": "",
                "urls": ["https://dl.google.com/android/repository/platform-tools_r36.0.0-darwin.zip"],
            },
        },
        "linux": {
            "build_tools": {
                "integrity": "",
                "urls": ["https://dl.google.com/android/repository/build-tools_r36.1-linux.zip"],
            },
            "emulator": {
                "integrity": "",
                "urls": ["https://dl.google.com/android/repository/emulator-linux_x64-14214601.zip"],
            },
            "platform": {
                "integrity": "",
                "strip_prefix": "android-14",
                "urls": ["https://dl.google.com/android/repository/platform-36_r02.zip"],
            },
            "platform_tools": {
                "integrity": "",
                "urls": ["https://dl.google.com/android/repository/platform-tools_r36.0.0-linux.zip"],
            },
        },
        "windows": {
            "build_tools": {
                "integrity": "",
                "urls": ["https://dl.google.com/android/repository/build-tools_r36.1-windows.zip"],
            },
            "emulator": {
                "integrity": "",
                "urls": ["https://dl.google.com/android/repository/emulator-windows_x64-14214601.zip"],
            },
            "platform": {
                "integrity": "",
                "strip_prefix": "android-14",
                "urls": ["https://dl.google.com/android/repository/platform-36_r02.zip"],
            },
            "platform_tools": {
                "integrity": "",
                "urls": ["https://dl.google.com/android/repository/platform-tools_r36.0.0-windows.zip"],
            },
        },
    },
}

ANDROID_PLATFORM_CONSTRAINTS = {
    "darwin": ["@platforms//os:macos"],
    "linux": ["@platforms//os:linux"],
    "windows": ["@platforms//os:windows"],
}

def _android_sdk_tools_repository_impl(repository_ctx):
    """Downloads and extracts Android SDK components."""
    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")""".format(
        repository_ctx.name,
    ))

    # Download and extract each component
    platform_tools_result = repository_ctx.download_and_extract(
        url = repository_ctx.attr.platform_tools_urls,
        stripPrefix = repository_ctx.attr.platform_tools_strip_prefix,
        output = "platform-tools",
        integrity = repository_ctx.attr.platform_tools_integrity,
    )

    build_tools_result = repository_ctx.download_and_extract(
        url = repository_ctx.attr.build_tools_urls,
        stripPrefix = repository_ctx.attr.build_tools_strip_prefix,
        output = "build-tools/36.1.0",
        integrity = repository_ctx.attr.build_tools_integrity,
    )

    platform_result = repository_ctx.download_and_extract(
        url = repository_ctx.attr.platform_urls,
        stripPrefix = repository_ctx.attr.platform_strip_prefix,
        output = "platforms/android-36",
        integrity = repository_ctx.attr.platform_integrity,
    )

    emulator_result = repository_ctx.download_and_extract(
        url = repository_ctx.attr.emulator_urls,
        stripPrefix = repository_ctx.attr.emulator_strip_prefix,
        output = "emulator",
        integrity = repository_ctx.attr.emulator_integrity,
    )

    repository_ctx.file("BUILD.bazel", repository_ctx.attr.build_file_content)

    return {
        "build_file_content": repository_ctx.attr.build_file_content,
        "build_tools_integrity": build_tools_result.integrity,
        "build_tools_strip_prefix": repository_ctx.attr.build_tools_strip_prefix,
        "build_tools_urls": repository_ctx.attr.build_tools_urls,
        "emulator_integrity": emulator_result.integrity,
        "emulator_strip_prefix": repository_ctx.attr.emulator_strip_prefix,
        "emulator_urls": repository_ctx.attr.emulator_urls,
        "name": repository_ctx.name,
        "platform_integrity": platform_result.integrity,
        "platform_strip_prefix": repository_ctx.attr.platform_strip_prefix,
        "platform_tools_integrity": platform_tools_result.integrity,
        "platform_tools_strip_prefix": repository_ctx.attr.platform_tools_strip_prefix,
        "platform_tools_urls": repository_ctx.attr.platform_tools_urls,
        "platform_urls": repository_ctx.attr.platform_urls,
    }

android_sdk_tools_repository = repository_rule(
    doc = """A repository rule for fetching and assembling Android SDK components.

    This rule downloads individual Android SDK components (platform-tools, build-tools,
    platform, and emulator) and assembles them into a standard Android SDK directory structure.
    The resulting repository can then be used with android_sdk_repository by passing its
    filesystem path.
    """,
    implementation = _android_sdk_tools_repository_impl,
    attrs = {
        "build_file_content": attr.string(
            doc = "Content for the BUILD.bazel file in the repository",
            mandatory = True,
        ),
        "build_tools_integrity": attr.string(
            doc = "Integrity hash for build-tools download",
            default = "",
        ),
        "build_tools_strip_prefix": attr.string(
            doc = "Directory prefix to strip from build-tools archive",
            default = "",
        ),
        "build_tools_urls": attr.string_list(
            doc = "URLs to download Android SDK build-tools from (contains aapt, dx, etc.)",
            mandatory = True,
        ),
        "emulator_integrity": attr.string(
            doc = "Integrity hash for emulator download",
            default = "",
        ),
        "emulator_strip_prefix": attr.string(
            doc = "Directory prefix to strip from emulator archive",
            default = "",
        ),
        "emulator_urls": attr.string_list(
            doc = "URLs to download Android emulator from",
            mandatory = True,
        ),
        "platform_integrity": attr.string(
            doc = "Integrity hash for platform download",
            default = "",
        ),
        "platform_strip_prefix": attr.string(
            doc = "Directory prefix to strip from platform archive",
            default = "",
        ),
        "platform_tools_integrity": attr.string(
            doc = "Integrity hash for platform-tools download",
            default = "",
        ),
        "platform_tools_strip_prefix": attr.string(
            doc = "Directory prefix to strip from platform-tools archive",
            default = "",
        ),
        "platform_tools_urls": attr.string_list(
            doc = "URLs to download Android SDK platform-tools from (contains adb, fastboot, etc.)",
            mandatory = True,
        ),
        "platform_urls": attr.string_list(
            doc = "URLs to download Android platform SDK from (contains android.jar, etc.)",
            mandatory = True,
        ),
    },
)

_SDK_HUB_CONTENT = """
package(default_visibility = ["//visibility:public"])

# The toolchain type used to distinguish Android SDK toolchains.
toolchain_type(name = "sdk_toolchain_type")

alias(
    name = "has_androidsdk",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:has_androidsdk",
        "@platforms//os:linux": "@{linux}//:has_androidsdk",
        "@platforms//os:windows": "@{windows}//:has_androidsdk",
    }},
)

# Platform-specific SDK aliases
alias(
    name = "sdk",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:sdk",
        "@platforms//os:linux": "@{linux}//:sdk",
        "@platforms//os:windows": "@{windows}//:sdk",
    }}),
)

alias(
    name = "sdk_path",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:sdk_path",
        "@platforms//os:linux": "@{linux}//:sdk_path",
        "@platforms//os:windows": "@{windows}//:sdk_path",
    }}),
)

# Platform tools aliases
alias(
    name = "adb",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:adb",
        "@platforms//os:linux": "@{linux}//:adb",
        "@platforms//os:windows": "@{windows}//:adb",
    }}),
)

# Build tools aliases
alias(
    name = "dexdump",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:dexdump",
        "@platforms//os:linux": "@{linux}//:dexdump",
        "@platforms//os:windows": "@{windows}//:dexdump",
    }}),
)

# Emulator aliases
alias(
    name = "emulator",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:emulator",
        "@platforms//os:linux": "@{linux}//:emulator",
        "@platforms//os:windows": "@{windows}//:emulator",
    }}),
)

alias(
    name = "emulator_arm",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:emulator_arm",
        "@platforms//os:linux": "@{linux}//:emulator_arm",
        "@platforms//os:windows": "@{windows}//:emulator_arm",
    }}),
)

alias(
    name = "emulator_x86",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:emulator_x86",
        "@platforms//os:linux": "@{linux}//:emulator_x86",
        "@platforms//os:windows": "@{windows}//:emulator_x86",
    }}),
)

alias(
    name = "mksd",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:mksd",
        "@platforms//os:linux": "@{linux}//:mksd",
        "@platforms//os:windows": "@{windows}//:mksd",
    }}),
)

alias(
    name = "emulator_x86_bios",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:emulator_x86_bios",
        "@platforms//os:linux": "@{linux}//:emulator_x86_bios",
        "@platforms//os:windows": "@{windows}//:emulator_x86_bios",
    }}),
)

alias(
    name = "emulator_shared_libs",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:emulator_shared_libs",
        "@platforms//os:linux": "@{linux}//:emulator_shared_libs",
        "@platforms//os:windows": "@{windows}//:emulator_shared_libs",
    }}),
)

alias(
    name = "qemu2_x86",
    actual = select({{
        "@platforms//os:macos": "@{darwin}//:qemu2_x86",
        "@platforms//os:linux": "@{linux}//:qemu2_x86",
        "@platforms//os:windows": "@{windows}//:qemu2_x86",
    }}),
)
"""

def _android_sdk_hub_impl(repository_ctx):
    """Creates a hub repository with platform-specific aliases."""
    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")""".format(
        repository_ctx.name,
    ))

    build_content = _SDK_HUB_CONTENT.format(
        darwin = repository_ctx.attr.sdk_repositories["darwin"],
        linux = repository_ctx.attr.sdk_repositories["linux"],
        windows = repository_ctx.attr.sdk_repositories["windows"],
    )

    repository_ctx.file("BUILD.bazel", build_content)

_android_sdk_hub = repository_rule(
    doc = "Creates a hub repository with platform-specific SDK aliases",
    implementation = _android_sdk_hub_impl,
    attrs = {
        "sdk_repositories": attr.string_dict(
            doc = "Mapping of platform names to SDK repository names",
            mandatory = True,
        ),
    },
)

def _android_sdk_extension_impl(module_ctx):
    """Module extension implementation for Android SDK.

    Downloads SDK components for each platform and assembles them into
    platform-specific SDK repositories.
    """
    api_level = "36"

    platforms = _ANDROID_SDK_COMPONENTS[api_level]

    sdk_repositories = {}

    for platform, components in platforms.items():
        sdk_name = "androidsdk_{}_{}".format(api_level, platform)
        tools_name = "{}_files".format(sdk_name)

        android_sdk_tools_repository(
            name = tools_name,
            platform_tools_urls = components["platform_tools"]["urls"],
            platform_tools_strip_prefix = components["platform_tools"].get("strip_prefix", ""),
            platform_tools_integrity = components["platform_tools"].get("integrity", ""),
            build_tools_urls = components["build_tools"]["urls"],
            build_tools_strip_prefix = components["build_tools"].get("strip_prefix", ""),
            build_tools_integrity = components["build_tools"].get("integrity", ""),
            platform_urls = components["platform"]["urls"],
            platform_strip_prefix = components["platform"].get("strip_prefix", ""),
            platform_integrity = components["platform"].get("integrity", ""),
            emulator_urls = components["emulator"]["urls"],
            emulator_strip_prefix = components["emulator"].get("strip_prefix", ""),
            emulator_integrity = components["emulator"].get("integrity", ""),
            build_file_content = """exports_files(glob(["**/*"]), visibility = ["//visibility:public"])""",
        )

        android_sdk_repository(
            name = sdk_name,
            anchor = str(Label("@@{}//:BUILD.bazel".format(tools_name))),
            api_level = int(api_level),
            build_tools_version = "36.1.0",
            register_toolchains = False,
        )

        sdk_repositories[platform] = sdk_name

    # Create a hub repository with aliases that select the right SDK based on exec platform
    _android_sdk_hub(
        name = "androidsdk",
        sdk_repositories = sdk_repositories,
    )

    return module_ctx.extension_metadata(
        reproducible = True,
        root_module_direct_deps = ["androidsdk"] + sdk_repositories.values(),
        root_module_direct_dev_deps = [],
    )

android_sdk = module_extension(
    doc = "Downloads and assembles Android SDK components",
    implementation = _android_sdk_extension_impl,
)
