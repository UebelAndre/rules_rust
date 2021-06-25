"""Utility functions for the crate_universe resolver"""

_CPU_ARCH_ERROR_MSG = """\
Command failed with exit code '{code}': {args}
----------stdout:
{stdout}
----------stderr:
{stderr}
"""

def _query_cpu_architecture(repository_ctx, expected_archs, is_windows = False):
    """Detect the host CPU architecture

    Args:
        repository_ctx (repository_ctx): The repository rule's context object
        expected_archs (list): A list of expected architecture strings
        is_windows (bool, optional): If true, the cpu lookup will use the windows method (`wmic` vs `uname`)

    Returns:
        str: The host's CPU architecture
    """
    if is_windows:
        arguments = ["wmic", "os", "get", "osarchitecture"]
    else:
        arguments = ["uname", "-m"]

    result = repository_ctx.execute(arguments)

    if result.return_code:
        fail(_CPU_ARCH_ERROR_MSG.format(
            code = result.return_code,
            args = arguments,
            stdout = result.stdout,
            stderr = result.stderr,
        ))

    if is_windows:
        # Example output:
        # OSArchitecture
        # 64-bit
        lines = result.stdout.split("\n")
        arch = lines[1].strip()

        # Translate 64-bit to a compatible rust platform
        # https://doc.rust-lang.org/nightly/rustc/platform-support.html
        if arch == "64-bit":
            arch = "x86_64"
    else:
        arch = result.stdout.strip("\n")

    if not arch in expected_archs:
        fail("{} is not a expected cpu architecture {}\n{}".format(
            arch,
            expected_archs,
            result.stdout,
        ))

    return arch

def get_host_info(repository_ctx):
    """Query host information for the appropriate triple and toolchain repo name

    Args:
        repository_ctx (repository_ctx): The rule's repository_ctx

    Returns:
        tuple: A tuple containing a triple (str) and repository name (str)
    """

    # Detect the host's cpu architecture

    supported_architectures = {
        "linux": ["aarch64", "x86_64"],
        "macos": ["aarch64", "x86_64"],
        "windows": ["x86_64"],
    }

    # The expected file extension of crate resolver binaries
    extension = ""

    if "linux" in repository_ctx.os.name:
        cpu = _query_cpu_architecture(repository_ctx, supported_architectures["linux"])
        resolver_triple = "{}-unknown-linux-gnu".format(cpu)
        toolchain_repo = "@rust_linux_{}".format(cpu)
    elif "mac" in repository_ctx.os.name:
        cpu = _query_cpu_architecture(repository_ctx, supported_architectures["macos"])
        resolver_triple = "{}-apple-darwin".format(cpu)
        toolchain_repo = "@rust_darwin_{}".format(cpu)
    elif "win" in repository_ctx.os.name:
        cpu = _query_cpu_architecture(repository_ctx, supported_architectures["windows"], True)
        resolver_triple = "{}-pc-windows-gnu".format(cpu)
        toolchain_repo = "@rust_windows_{}".format(cpu)
        extension = ".exe"
    else:
        fail("Could not locate resolver for OS " + repository_ctx.os.name)

    return (resolver_triple, toolchain_repo, extension)

def dedent(doc_string):
    """Tidy excess whitespace in docstrings to not break index.md

    Args:
        doc_string (str): A docstring style string

    Returns:
        str: A string optimized for stardoc rendering
    """
    lines = doc_string.splitlines()
    if not lines:
        return doc_string

    # If the first line is empty, use the second line
    first_line = lines[0]
    if not first_line:
        first_line = lines[1]

    # Detect how much space prepends the first line and subtract that from all lines
    space_count = len(first_line) - len(first_line.lstrip())

    # If there are no leading spaces, do not alter the docstring
    if space_count == 0:
        return doc_string
    else:
        # Remove the leading block of spaces from the current line
        block = " " * space_count
        return "\n".join([line.replace(block, "", 1).rstrip() for line in lines])
