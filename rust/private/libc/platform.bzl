"""The C standard library the target platform declares, as a flag."""

def _platform_libc_flag_impl(ctx):
    return [config_common.FeatureFlagInfo(value = ctx.attr.libc)]

platform_libc_flag = rule(
    doc = """\
Exposes the C standard library the target platform declares to `select()`.

`libc` is a `select()` over settings on the `platforms_contrib` constraints, see
`//rust/private/libc:BUILD.bazel`: `glibc` or `musl` for a platform declaring
one of them available, `glibc` for a platform declaring both, empty for a
platform declaring neither.
""",
    implementation = _platform_libc_flag_impl,
    attrs = {
        "libc": attr.string(
            doc = "The libc the target platform declares: `glibc`, `musl` or empty.",
            mandatory = True,
        ),
    },
)
