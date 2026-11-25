"""The C standard library of a build, as a flag combining its sources."""

def _libc_flag_impl(ctx):
    for authority in ctx.attr.authorities:
        libc = authority[config_common.FeatureFlagInfo].value
        if libc:
            return [config_common.FeatureFlagInfo(value = libc)]
    return [config_common.FeatureFlagInfo(value = "")]

libc_flag = rule(
    doc = """\
Exposes the C standard library of a build to `select()`.

The value is that of the first of `authorities` which names one, or empty when
none does, in which case a `select()` on the settings takes its default. Read in
the target configuration it describes the target platform's libc, in the exec
configuration the execution platform's.
""",
    implementation = _libc_flag_impl,
    attrs = {
        "authorities": attr.label_list(
            doc = "Flags reporting the libc, in order of precedence; see `platform.bzl` and `cc_toolchain.bzl`.",
            providers = [config_common.FeatureFlagInfo],
            mandatory = True,
        ),
    },
)
