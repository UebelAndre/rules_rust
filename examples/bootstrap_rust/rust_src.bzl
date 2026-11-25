"""The source of a Rust release, with BUILD files of the example's own in it.

`rustc-<version>-src.tar.xz` is the whole tree: `library/`, the compiler, the
tools under `src/tools/` and every third-party crate they depend on, vendored
under `vendor/`. The crates built from it, rustdoc and Clippy, read files
relative to `CARGO_MANIFEST_DIR`, which rules_rust sets to the package of the
target, so their BUILD files have to be in the tree, in the crates' own
directories. `http_archive` writes one BUILD file, at the root; this writes
one per package named in `build_files`.
"""

def _rust_src_repository_impl(repository_ctx):
    version = repository_ctx.attr.version
    repository_ctx.download_and_extract(
        url = "https://static.rust-lang.org/dist/rustc-{}-src.tar.xz".format(version),
        sha256 = repository_ctx.attr.sha256,
        stripPrefix = "rustc-{}-src".format(version),
    )
    for build_file, package in repository_ctx.attr.build_files.items():
        repository_ctx.file(
            "{}/BUILD.bazel".format(package) if package else "BUILD.bazel",
            repository_ctx.read(build_file),
        )

    # `vendor/` holds every version of a crate any workspace in the tree
    # depends on; `library/Cargo.lock` says which the standard library does.
    repository_ctx.file(
        "vendored.bzl",
        "\n".join([
            '"""The versions `library/Cargo.lock` pins, as `vendor/` directory names by crate. Generated."""',
            "",
            "LIBRARY_VENDORED = {",
        ] + [
            '    "{}": {},'.format(name, repr(sorted(["{}-{}".format(name, version) for version in versions])))
            for name, versions in sorted(_locked_versions(repository_ctx.read("library/Cargo.lock")).items())
        ] + [
            "}",
            "",
        ]),
    )
    return repository_ctx.repo_metadata(reproducible = True)

def _locked_versions(lockfile):
    """The versions each package has in a `Cargo.lock`.

    Args:
        lockfile (str): The lockfile's content.

    Returns:
        dict[str, list[str]]: The versions, by package name.
    """
    versions = {}
    name = None
    for line in lockfile.splitlines():
        if line == "[[package]]":
            name = None
        elif line.startswith("name = "):
            name = line[len("name = "):].strip('"')
        elif line.startswith("version = ") and name:
            versions.setdefault(name, []).append(line[len("version = "):].strip('"'))
    return versions

rust_src_repository = repository_rule(
    implementation = _rust_src_repository_impl,
    doc = "The source tarball of a Rust release, with the example's BUILD files written into it.",
    attrs = {
        "build_files": attr.label_keyed_string_dict(
            doc = "BUILD files to write, keyed by the file and valued with the package to write it to (`\"\"` for the root).",
            allow_files = True,
            mandatory = True,
        ),
        "sha256": attr.string(
            doc = "The checksum of the tarball, from `rustc-<version>-src.tar.xz.sha256`.",
            mandatory = True,
        ),
        "version": attr.string(
            doc = "The release.",
            mandatory = True,
        ),
    },
)
