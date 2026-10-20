"""Helpers for laying out Rust tools in a generated sysroot.

`rustc`, `rustdoc` and `clippy-driver` are all drivers linked against
`librustc_driver`, which they find relative to their own location
(`$ORIGIN/../lib`), and they look for codegen backends and `rust-lld` under
the sysroot their own path resolves to. Locally that path is canonicalized
to the downloaded distribution, but remote executors materialize declared
symlinks as copies, so every toolchain which runs one of these drivers must
reproduce the `bin/<tool>` + `lib/...` layout next to the tool itself. These
helpers build that layout out of symlinks.
"""

def symlink_sysroot_tree(ctx, name, target, target_files = None):
    """Generate a set of symlinks to files from another target

    Args:
        ctx (ctx): The toolchain's context object
        name (str): The name of the sysroot directory (typically `ctx.label.name`)
        target (Target): A target owning files to symlink
        target_files (depset): An optional depset to use in place of `target.files`.

    Returns:
        depset[File]: A depset of the generated symlink files
    """
    tree_files = []
    if target_files == None:
        target_files = target.files
    for file in target_files.to_list():
        # Parse the path to the file relative to the workspace root so a
        # symlink matching this path can be created within the sysroot.

        # The code blow attempts to parse any workspace names out of the
        # path. For local targets, this code is a noop.
        if target.label.workspace_root:
            file_path = file.path.split(target.label.workspace_root, 1)[-1]
        else:
            file_path = file.path

        symlink = ctx.actions.declare_file("{}/{}".format(name, file_path.lstrip("/")))

        ctx.actions.symlink(
            output = symlink,
            target_file = file,
        )

        tree_files.append(symlink)

    return depset(tree_files)

def symlink_sysroot_bin(ctx, name, directory, target):
    """Crete a symlink to a target file.

    Args:
        ctx (ctx): The rule's context object
        name (str): A common name for the output directory
        directory (str): The directory under `name` to put the file in
        target (File): A File object to symlink to

    Returns:
        File: A newly generated symlink file
    """
    symlink = ctx.actions.declare_file("{}/{}/{}".format(
        name,
        directory,
        target.basename,
    ))

    ctx.actions.symlink(
        output = symlink,
        target_file = target,
        is_executable = True,
    )

    return symlink
