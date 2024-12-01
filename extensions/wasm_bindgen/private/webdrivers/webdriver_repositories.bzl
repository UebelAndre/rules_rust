"""Depednencies for `wasm_bindgen_test` rules"""

def _build_file_repository_impl(repository_ctx):
    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")""".format(
        repository_ctx.name,
    ))

    repository_ctx.file("BUILD.bazel", repository_ctx.read(repository_ctx.path(repository_ctx.attr.build_file)))

build_file_repository = repository_rule(
    doc = "A repository rule for generating external repositories with a specific build file.",
    implementation = _build_file_repository_impl,
    attrs = {
        "build_file": attr.label(
            doc = "The file to use as the BUILD file for this repository.",
            mandatory = True,
            allow_Files = True,
        ),
    },
)

def firefox_deps():
    # https://ftp.mozilla.org/pub/firefox/releases/129.0/

    geckodriver_version = "0.35.0"

    for platform, integrity in {
        "linux-aarch64": "",
        "linux64": "",
        "macos": "",
        "macos-aarch64": "",
        "win64": "",
    }.items():
        archive = "tar.gz"
        if "win" in platform:
            archive = "zip"

        maybe(
            http_archive,
            name = "geckodriver_{}".format(platform.replace("-", "_")),
            urls = ["https://github.com/mozilla/geckodriver/releases/download/v{version}/geckodriver-v{version}-{platform}.{archive}".format(
                version = geckodriver_version,
                platform = platform,
                archive = archive,
            )],
            integrity = integrity,
        )

    maybe(
        build_file_repository,
        name = "geckodriver",
        build_file = Label("//wasm_bindgen/private/webdrivers:BUILD.geckodriver.bazel"),
    )

# A snippet from https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json
# but modified to included `integrity`
CHROME_DATA = {
    "downloads": {
        "chrome": [
            {
                "platform": "linux64",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/linux64/chrome-linux64.zip",
            },
            {
                "integrity": "sha256-wpo/MrA8jvaqjPvLfUUTqQ629dsvYMg+7Y0bnXScGZI=",
                "platform": "mac-arm64",
                "strip_prefix": "chrome-mac-arm64/Google Chrome for Testing.app/Contents",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/mac-arm64/chrome-mac-arm64.zip",
            },
            {
                "platform": "mac-x64",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/mac-x64/chrome-mac-x64.zip",
            },
            {
                "platform": "win32",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/win32/chrome-win32.zip",
            },
            {
                "platform": "win64",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/win64/chrome-win64.zip",
            },
        ],
        "chrome-headless-shell": [
            {
                "platform": "linux64",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/linux64/chrome-headless-shell-linux64.zip",
            },
            {
                "platform": "mac-arm64",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/mac-arm64/chrome-headless-shell-mac-arm64.zip",
            },
            {
                "platform": "mac-x64",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/mac-x64/chrome-headless-shell-mac-x64.zip",
            },
            {
                "platform": "win32",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/win32/chrome-headless-shell-win32.zip",
            },
            {
                "platform": "win64",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/win64/chrome-headless-shell-win64.zip",
            },
        ],
        "chromedriver": [
            {
                "platform": "linux64",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/linux64/chromedriver-linux64.zip",
            },
            {
                "platform": "mac-arm64",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/mac-arm64/chromedriver-mac-arm64.zip",
            },
            {
                "platform": "mac-x64",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/mac-x64/chromedriver-mac-x64.zip",
            },
            {
                "platform": "win32",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/win32/chromedriver-win32.zip",
            },
            {
                "platform": "win64",
                "url": "https://storage.googleapis.com/chrome-for-testing-public/121.0.6127.0/win64/chromedriver-win64.zip",
            },
        ],
    },
    "revision": "1224055",
    "version": "121.0.6127.0",
}

def chrome_deps():
    for data in CHROME_DATA["downloads"]["chromedriver"]:
        platform = data["platform"].replace("-", "_")
        maybe(
            http_archive,
            name = "chromedriver_{}".format(platform),
            urls = [data["url"]],
            integrity = data.get("integrity", ""),
        )

    maybe(
        build_file_repository,
        name = "chromedriver",
        build_file = Label("//wasm_bindgen/private/webdrivers:BUILD.chromedriver.bazel"),
    )
