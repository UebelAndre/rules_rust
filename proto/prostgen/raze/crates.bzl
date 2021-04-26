"""
@generated
cargo-raze generated Bazel file.

DO NOT EDIT! Replaced on runs of cargo-raze
"""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")  # buildifier: disable=load
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")  # buildifier: disable=load
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")  # buildifier: disable=load

def rules_rust_prostgen_fetch_remote_crates():
    """This function defines a collection of repos and should be called in a WORKSPACE file"""
    maybe(
        http_archive,
        name = "rules_rust_prostgen__anyhow__1_0_31",
        url = "https://crates.io/api/v1/crates/anyhow/1.0.31/download",
        type = "tar.gz",
        sha256 = "85bb70cc08ec97ca5450e6eba421deeea5f172c0fc61f78b5357b2a8e8be195f",
        strip_prefix = "anyhow-1.0.31",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.anyhow-1.0.31.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__async_stream__0_2_1",
        url = "https://crates.io/api/v1/crates/async-stream/0.2.1/download",
        type = "tar.gz",
        sha256 = "22068c0c19514942eefcfd4daf8976ef1aad84e61539f95cd200c35202f80af5",
        strip_prefix = "async-stream-0.2.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.async-stream-0.2.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__async_stream_impl__0_2_1",
        url = "https://crates.io/api/v1/crates/async-stream-impl/0.2.1/download",
        type = "tar.gz",
        sha256 = "25f9db3b38af870bf7e5cc649167533b493928e50744e2c30ae350230b414670",
        strip_prefix = "async-stream-impl-0.2.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.async-stream-impl-0.2.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__async_trait__0_1_42",
        url = "https://crates.io/api/v1/crates/async-trait/0.1.42/download",
        type = "tar.gz",
        sha256 = "8d3a45e77e34375a7923b1e8febb049bb011f064714a8e17a1a616fef01da13d",
        strip_prefix = "async-trait-0.1.42",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.async-trait-0.1.42.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__autocfg__1_0_1",
        url = "https://crates.io/api/v1/crates/autocfg/1.0.1/download",
        type = "tar.gz",
        sha256 = "cdb031dd78e28731d87d56cc8ffef4a8f36ca26c38fe2de700543e627f8a464a",
        strip_prefix = "autocfg-1.0.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.autocfg-1.0.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__base64__0_12_3",
        url = "https://crates.io/api/v1/crates/base64/0.12.3/download",
        type = "tar.gz",
        sha256 = "3441f0f7b02788e948e47f457ca01f1d7e6d92c693bc132c22b087d3141c03ff",
        strip_prefix = "base64-0.12.3",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.base64-0.12.3.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__bitflags__1_2_1",
        url = "https://crates.io/api/v1/crates/bitflags/1.2.1/download",
        type = "tar.gz",
        sha256 = "cf1de2fe8c75bc145a2f577add951f8134889b4795d47466a54a5c846d691693",
        strip_prefix = "bitflags-1.2.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.bitflags-1.2.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__bumpalo__3_6_1",
        url = "https://crates.io/api/v1/crates/bumpalo/3.6.1/download",
        type = "tar.gz",
        sha256 = "63396b8a4b9de3f4fdfb320ab6080762242f66a8ef174c49d8e19b674db4cdbe",
        strip_prefix = "bumpalo-3.6.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.bumpalo-3.6.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__bytes__0_5_6",
        url = "https://crates.io/api/v1/crates/bytes/0.5.6/download",
        type = "tar.gz",
        sha256 = "0e4cec68f03f32e44924783795810fa50a7035d8c8ebe78580ad7e6c703fba38",
        strip_prefix = "bytes-0.5.6",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.bytes-0.5.6.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__bytes__1_0_1",
        url = "https://crates.io/api/v1/crates/bytes/1.0.1/download",
        type = "tar.gz",
        sha256 = "b700ce4376041dcd0a327fd0097c41095743c4c8af8887265942faf1100bd040",
        strip_prefix = "bytes-1.0.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.bytes-1.0.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__cc__1_0_67",
        url = "https://crates.io/api/v1/crates/cc/1.0.67/download",
        type = "tar.gz",
        sha256 = "e3c69b077ad434294d3ce9f1f6143a2a4b89a8a2d54ef813d85003a4fd1137fd",
        strip_prefix = "cc-1.0.67",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.cc-1.0.67.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__cfg_if__0_1_10",
        url = "https://crates.io/api/v1/crates/cfg-if/0.1.10/download",
        type = "tar.gz",
        sha256 = "4785bdd1c96b2a846b2bd7cc02e86b6b3dbf14e7e53446c4f54c92a361040822",
        strip_prefix = "cfg-if-0.1.10",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.cfg-if-0.1.10.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__cfg_if__1_0_0",
        url = "https://crates.io/api/v1/crates/cfg-if/1.0.0/download",
        type = "tar.gz",
        sha256 = "baf1de4339761588bc0619e3cbc0120ee582ebb74b53b4efbf79117bd2da40fd",
        strip_prefix = "cfg-if-1.0.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.cfg-if-1.0.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__clap__2_33_3",
        url = "https://crates.io/api/v1/crates/clap/2.33.3/download",
        type = "tar.gz",
        sha256 = "37e58ac78573c40708d45522f0d80fa2f01cc4f9b4e2bf749807255454312002",
        strip_prefix = "clap-2.33.3",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.clap-2.33.3.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__core_foundation__0_7_0",
        url = "https://crates.io/api/v1/crates/core-foundation/0.7.0/download",
        type = "tar.gz",
        sha256 = "57d24c7a13c43e870e37c1556b74555437870a04514f7685f5b354e090567171",
        strip_prefix = "core-foundation-0.7.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.core-foundation-0.7.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__core_foundation_sys__0_7_0",
        url = "https://crates.io/api/v1/crates/core-foundation-sys/0.7.0/download",
        type = "tar.gz",
        sha256 = "b3a71ab494c0b5b860bdc8407ae08978052417070c2ced38573a9157ad75b8ac",
        strip_prefix = "core-foundation-sys-0.7.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.core-foundation-sys-0.7.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__either__1_6_1",
        url = "https://crates.io/api/v1/crates/either/1.6.1/download",
        type = "tar.gz",
        sha256 = "e78d4f1cc4ae33bbfc157ed5d5a5ef3bc29227303d595861deb238fcec4e9457",
        strip_prefix = "either-1.6.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.either-1.6.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__fixedbitset__0_2_0",
        url = "https://crates.io/api/v1/crates/fixedbitset/0.2.0/download",
        type = "tar.gz",
        sha256 = "37ab347416e802de484e4d03c7316c48f1ecb56574dfd4a46a80f173ce1de04d",
        strip_prefix = "fixedbitset-0.2.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.fixedbitset-0.2.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__fnv__1_0_7",
        url = "https://crates.io/api/v1/crates/fnv/1.0.7/download",
        type = "tar.gz",
        sha256 = "3f9eec918d3f24069decb9af1554cad7c880e2da24a9afd88aca000531ab82c1",
        strip_prefix = "fnv-1.0.7",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.fnv-1.0.7.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__fuchsia_zircon__0_3_3",
        url = "https://crates.io/api/v1/crates/fuchsia-zircon/0.3.3/download",
        type = "tar.gz",
        sha256 = "2e9763c69ebaae630ba35f74888db465e49e259ba1bc0eda7d06f4a067615d82",
        strip_prefix = "fuchsia-zircon-0.3.3",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.fuchsia-zircon-0.3.3.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__fuchsia_zircon_sys__0_3_3",
        url = "https://crates.io/api/v1/crates/fuchsia-zircon-sys/0.3.3/download",
        type = "tar.gz",
        sha256 = "3dcaa9ae7725d12cdb85b3ad99a434db70b468c09ded17e012d86b5c1010f7a7",
        strip_prefix = "fuchsia-zircon-sys-0.3.3",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.fuchsia-zircon-sys-0.3.3.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__futures_channel__0_3_12",
        url = "https://crates.io/api/v1/crates/futures-channel/0.3.12/download",
        type = "tar.gz",
        sha256 = "f2d31b7ec7efab6eefc7c57233bb10b847986139d88cc2f5a02a1ae6871a1846",
        strip_prefix = "futures-channel-0.3.12",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.futures-channel-0.3.12.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__futures_core__0_3_12",
        url = "https://crates.io/api/v1/crates/futures-core/0.3.12/download",
        type = "tar.gz",
        sha256 = "79e5145dde8da7d1b3892dad07a9c98fc04bc39892b1ecc9692cf53e2b780a65",
        strip_prefix = "futures-core-0.3.12",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.futures-core-0.3.12.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__futures_sink__0_3_12",
        url = "https://crates.io/api/v1/crates/futures-sink/0.3.12/download",
        type = "tar.gz",
        sha256 = "caf5c69029bda2e743fddd0582d1083951d65cc9539aebf8812f36c3491342d6",
        strip_prefix = "futures-sink-0.3.12",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.futures-sink-0.3.12.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__futures_task__0_3_12",
        url = "https://crates.io/api/v1/crates/futures-task/0.3.12/download",
        type = "tar.gz",
        sha256 = "13de07eb8ea81ae445aca7b69f5f7bf15d7bf4912d8ca37d6645c77ae8a58d86",
        strip_prefix = "futures-task-0.3.12",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.futures-task-0.3.12.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__futures_util__0_3_12",
        url = "https://crates.io/api/v1/crates/futures-util/0.3.12/download",
        type = "tar.gz",
        sha256 = "632a8cd0f2a4b3fdea1657f08bde063848c3bd00f9bbf6e256b8be78802e624b",
        strip_prefix = "futures-util-0.3.12",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.futures-util-0.3.12.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__getrandom__0_1_16",
        url = "https://crates.io/api/v1/crates/getrandom/0.1.16/download",
        type = "tar.gz",
        sha256 = "8fc3cb4d91f53b50155bdcfd23f6a4c39ae1969c2ae85982b135750cccaf5fce",
        strip_prefix = "getrandom-0.1.16",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.getrandom-0.1.16.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__getrandom__0_2_2",
        url = "https://crates.io/api/v1/crates/getrandom/0.2.2/download",
        type = "tar.gz",
        sha256 = "c9495705279e7140bf035dde1f6e750c162df8b625267cd52cc44e0b156732c8",
        strip_prefix = "getrandom-0.2.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.getrandom-0.2.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__h2__0_2_7",
        url = "https://crates.io/api/v1/crates/h2/0.2.7/download",
        type = "tar.gz",
        sha256 = "5e4728fd124914ad25e99e3d15a9361a879f6620f63cb56bbb08f95abb97a535",
        strip_prefix = "h2-0.2.7",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.h2-0.2.7.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__hashbrown__0_9_1",
        url = "https://crates.io/api/v1/crates/hashbrown/0.9.1/download",
        type = "tar.gz",
        sha256 = "d7afe4a420e3fe79967a00898cc1f4db7c8a49a9333a29f8a4bd76a253d5cd04",
        strip_prefix = "hashbrown-0.9.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.hashbrown-0.9.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__heck__0_3_1",
        url = "https://crates.io/api/v1/crates/heck/0.3.1/download",
        type = "tar.gz",
        sha256 = "20564e78d53d2bb135c343b3f47714a56af2061f1c928fdb541dc7b9fdd94205",
        strip_prefix = "heck-0.3.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.heck-0.3.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__http__0_2_3",
        url = "https://crates.io/api/v1/crates/http/0.2.3/download",
        type = "tar.gz",
        sha256 = "7245cd7449cc792608c3c8a9eaf69bd4eabbabf802713748fd739c98b82f0747",
        strip_prefix = "http-0.2.3",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.http-0.2.3.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__http_body__0_3_1",
        url = "https://crates.io/api/v1/crates/http-body/0.3.1/download",
        type = "tar.gz",
        sha256 = "13d5ff830006f7646652e057693569bfe0d51760c0085a071769d142a205111b",
        strip_prefix = "http-body-0.3.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.http-body-0.3.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__httparse__1_3_5",
        url = "https://crates.io/api/v1/crates/httparse/1.3.5/download",
        type = "tar.gz",
        sha256 = "615caabe2c3160b313d52ccc905335f4ed5f10881dd63dc5699d47e90be85691",
        strip_prefix = "httparse-1.3.5",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.httparse-1.3.5.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__hyper__0_13_6",
        url = "https://crates.io/api/v1/crates/hyper/0.13.6/download",
        type = "tar.gz",
        sha256 = "a6e7655b9594024ad0ee439f3b5a7299369dc2a3f459b47c696f9ff676f9aa1f",
        strip_prefix = "hyper-0.13.6",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.hyper-0.13.6.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__indexmap__1_6_1",
        url = "https://crates.io/api/v1/crates/indexmap/1.6.1/download",
        type = "tar.gz",
        sha256 = "4fb1fa934250de4de8aef298d81c729a7d33d8c239daa3a7575e6b92bfc7313b",
        strip_prefix = "indexmap-1.6.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.indexmap-1.6.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__iovec__0_1_4",
        url = "https://crates.io/api/v1/crates/iovec/0.1.4/download",
        type = "tar.gz",
        sha256 = "b2b3ea6ff95e175473f8ffe6a7eb7c00d054240321b84c57051175fe3c1e075e",
        strip_prefix = "iovec-0.1.4",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.iovec-0.1.4.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__itertools__0_8_2",
        url = "https://crates.io/api/v1/crates/itertools/0.8.2/download",
        type = "tar.gz",
        sha256 = "f56a2d0bc861f9165be4eb3442afd3c236d8a98afd426f65d92324ae1091a484",
        strip_prefix = "itertools-0.8.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.itertools-0.8.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__itoa__0_4_7",
        url = "https://crates.io/api/v1/crates/itoa/0.4.7/download",
        type = "tar.gz",
        sha256 = "dd25036021b0de88a0aff6b850051563c6516d0bf53f8638938edbb9de732736",
        strip_prefix = "itoa-0.4.7",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.itoa-0.4.7.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__js_sys__0_3_47",
        url = "https://crates.io/api/v1/crates/js-sys/0.3.47/download",
        type = "tar.gz",
        sha256 = "5cfb73131c35423a367daf8cbd24100af0d077668c8c2943f0e7dd775fef0f65",
        strip_prefix = "js-sys-0.3.47",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.js-sys-0.3.47.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__kernel32_sys__0_2_2",
        url = "https://crates.io/api/v1/crates/kernel32-sys/0.2.2/download",
        type = "tar.gz",
        sha256 = "7507624b29483431c0ba2d82aece8ca6cdba9382bff4ddd0f7490560c056098d",
        strip_prefix = "kernel32-sys-0.2.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.kernel32-sys-0.2.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__lazy_static__1_4_0",
        url = "https://crates.io/api/v1/crates/lazy_static/1.4.0/download",
        type = "tar.gz",
        sha256 = "e2abad23fbc42b3700f2f279844dc832adb2b2eb069b2df918f455c4e18cc646",
        strip_prefix = "lazy_static-1.4.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.lazy_static-1.4.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__libc__0_2_86",
        url = "https://crates.io/api/v1/crates/libc/0.2.86/download",
        type = "tar.gz",
        sha256 = "b7282d924be3275cec7f6756ff4121987bc6481325397dde6ba3e7802b1a8b1c",
        strip_prefix = "libc-0.2.86",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.libc-0.2.86.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__log__0_4_14",
        url = "https://crates.io/api/v1/crates/log/0.4.14/download",
        type = "tar.gz",
        sha256 = "51b9bbe6c47d51fc3e1a9b945965946b4c44142ab8792c50835a980d362c2710",
        strip_prefix = "log-0.4.14",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.log-0.4.14.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__memchr__2_3_4",
        url = "https://crates.io/api/v1/crates/memchr/2.3.4/download",
        type = "tar.gz",
        sha256 = "0ee1c47aaa256ecabcaea351eae4a9b01ef39ed810004e298d2511ed284b1525",
        strip_prefix = "memchr-2.3.4",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.memchr-2.3.4.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__mio__0_6_23",
        url = "https://crates.io/api/v1/crates/mio/0.6.23/download",
        type = "tar.gz",
        sha256 = "4afd66f5b91bf2a3bc13fad0e21caedac168ca4c707504e75585648ae80e4cc4",
        strip_prefix = "mio-0.6.23",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.mio-0.6.23.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__miow__0_2_2",
        url = "https://crates.io/api/v1/crates/miow/0.2.2/download",
        type = "tar.gz",
        sha256 = "ebd808424166322d4a38da87083bfddd3ac4c131334ed55856112eb06d46944d",
        strip_prefix = "miow-0.2.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.miow-0.2.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__multimap__0_8_2",
        url = "https://crates.io/api/v1/crates/multimap/0.8.2/download",
        type = "tar.gz",
        sha256 = "1255076139a83bb467426e7f8d0134968a8118844faa755985e077cf31850333",
        strip_prefix = "multimap-0.8.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.multimap-0.8.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__net2__0_2_37",
        url = "https://crates.io/api/v1/crates/net2/0.2.37/download",
        type = "tar.gz",
        sha256 = "391630d12b68002ae1e25e8f974306474966550ad82dac6886fb8910c19568ae",
        strip_prefix = "net2-0.2.37",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.net2-0.2.37.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__once_cell__1_5_2",
        url = "https://crates.io/api/v1/crates/once_cell/1.5.2/download",
        type = "tar.gz",
        sha256 = "13bd41f508810a131401606d54ac32a467c97172d74ba7662562ebba5ad07fa0",
        strip_prefix = "once_cell-1.5.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.once_cell-1.5.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__openssl_probe__0_1_2",
        url = "https://crates.io/api/v1/crates/openssl-probe/0.1.2/download",
        type = "tar.gz",
        sha256 = "77af24da69f9d9341038eba93a073b1fdaaa1b788221b00a69bce9e762cb32de",
        strip_prefix = "openssl-probe-0.1.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.openssl-probe-0.1.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__percent_encoding__2_1_0",
        url = "https://crates.io/api/v1/crates/percent-encoding/2.1.0/download",
        type = "tar.gz",
        sha256 = "d4fd5641d01c8f18a23da7b6fe29298ff4b55afcccdf78973b24cf3175fee32e",
        strip_prefix = "percent-encoding-2.1.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.percent-encoding-2.1.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__petgraph__0_5_1",
        url = "https://crates.io/api/v1/crates/petgraph/0.5.1/download",
        type = "tar.gz",
        sha256 = "467d164a6de56270bd7c4d070df81d07beace25012d5103ced4e9ff08d6afdb7",
        strip_prefix = "petgraph-0.5.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.petgraph-0.5.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__pin_project__0_4_26",
        url = "https://crates.io/api/v1/crates/pin-project/0.4.26/download",
        type = "tar.gz",
        sha256 = "13fbdfd6bdee3dc9be46452f86af4a4072975899cf8592466668620bebfbcc17",
        strip_prefix = "pin-project-0.4.26",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.pin-project-0.4.26.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__pin_project_internal__0_4_26",
        url = "https://crates.io/api/v1/crates/pin-project-internal/0.4.26/download",
        type = "tar.gz",
        sha256 = "c82fb1329f632c3552cf352d14427d57a511b1cf41db93b3a7d77906a82dcc8e",
        strip_prefix = "pin-project-internal-0.4.26",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.pin-project-internal-0.4.26.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__pin_project_lite__0_1_11",
        url = "https://crates.io/api/v1/crates/pin-project-lite/0.1.11/download",
        type = "tar.gz",
        sha256 = "c917123afa01924fc84bb20c4c03f004d9c38e5127e3c039bbf7f4b9c76a2f6b",
        strip_prefix = "pin-project-lite-0.1.11",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.pin-project-lite-0.1.11.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__pin_project_lite__0_2_4",
        url = "https://crates.io/api/v1/crates/pin-project-lite/0.2.4/download",
        type = "tar.gz",
        sha256 = "439697af366c49a6d0a010c56a0d97685bc140ce0d377b13a2ea2aa42d64a827",
        strip_prefix = "pin-project-lite-0.2.4",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.pin-project-lite-0.2.4.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__pin_utils__0_1_0",
        url = "https://crates.io/api/v1/crates/pin-utils/0.1.0/download",
        type = "tar.gz",
        sha256 = "8b870d8c151b6f2fb93e84a13146138f05d02ed11c7e7c54f8826aaaf7c9f184",
        strip_prefix = "pin-utils-0.1.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.pin-utils-0.1.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__ppv_lite86__0_2_10",
        url = "https://crates.io/api/v1/crates/ppv-lite86/0.2.10/download",
        type = "tar.gz",
        sha256 = "ac74c624d6b2d21f425f752262f42188365d7b8ff1aff74c82e45136510a4857",
        strip_prefix = "ppv-lite86-0.2.10",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.ppv-lite86-0.2.10.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__proc_macro_error__1_0_2",
        url = "https://crates.io/api/v1/crates/proc-macro-error/1.0.2/download",
        type = "tar.gz",
        sha256 = "98e9e4b82e0ef281812565ea4751049f1bdcdfccda7d3f459f2e138a40c08678",
        strip_prefix = "proc-macro-error-1.0.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.proc-macro-error-1.0.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__proc_macro_error_attr__1_0_2",
        url = "https://crates.io/api/v1/crates/proc-macro-error-attr/1.0.2/download",
        type = "tar.gz",
        sha256 = "4f5444ead4e9935abd7f27dc51f7e852a0569ac888096d5ec2499470794e2e53",
        strip_prefix = "proc-macro-error-attr-1.0.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.proc-macro-error-attr-1.0.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__proc_macro2__1_0_18",
        url = "https://crates.io/api/v1/crates/proc-macro2/1.0.18/download",
        type = "tar.gz",
        sha256 = "beae6331a816b1f65d04c45b078fd8e6c93e8071771f41b8163255bbd8d7c8fa",
        strip_prefix = "proc-macro2-1.0.18",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.proc-macro2-1.0.18.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__prost__0_6_1",
        url = "https://crates.io/api/v1/crates/prost/0.6.1/download",
        type = "tar.gz",
        sha256 = "ce49aefe0a6144a45de32927c77bd2859a5f7677b55f220ae5b744e87389c212",
        strip_prefix = "prost-0.6.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.prost-0.6.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__prost_build__0_6_1",
        url = "https://crates.io/api/v1/crates/prost-build/0.6.1/download",
        type = "tar.gz",
        sha256 = "02b10678c913ecbd69350e8535c3aef91a8676c0773fc1d7b95cdd196d7f2f26",
        strip_prefix = "prost-build-0.6.1",
        patches = [
            "//proto/prostgen/raze/patches:prost-build-0.6.1.patch",
        ],
        patch_args = [
            "-p1",
        ],
        build_file = Label("//proto/prostgen/raze/remote:BUILD.prost-build-0.6.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__prost_derive__0_6_1",
        url = "https://crates.io/api/v1/crates/prost-derive/0.6.1/download",
        type = "tar.gz",
        sha256 = "537aa19b95acde10a12fec4301466386f757403de4cd4e5b4fa78fb5ecb18f72",
        strip_prefix = "prost-derive-0.6.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.prost-derive-0.6.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__prost_types__0_6_1",
        url = "https://crates.io/api/v1/crates/prost-types/0.6.1/download",
        type = "tar.gz",
        sha256 = "1834f67c0697c001304b75be76f67add9c89742eda3a085ad8ee0bb38c3417aa",
        strip_prefix = "prost-types-0.6.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.prost-types-0.6.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__quote__1_0_7",
        url = "https://crates.io/api/v1/crates/quote/1.0.7/download",
        type = "tar.gz",
        sha256 = "aa563d17ecb180e500da1cfd2b028310ac758de548efdd203e18f283af693f37",
        strip_prefix = "quote-1.0.7",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.quote-1.0.7.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__rand__0_7_3",
        url = "https://crates.io/api/v1/crates/rand/0.7.3/download",
        type = "tar.gz",
        sha256 = "6a6b1679d49b24bbfe0c803429aa1874472f50d9b363131f0e89fc356b544d03",
        strip_prefix = "rand-0.7.3",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.rand-0.7.3.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__rand__0_8_3",
        url = "https://crates.io/api/v1/crates/rand/0.8.3/download",
        type = "tar.gz",
        sha256 = "0ef9e7e66b4468674bfcb0c81af8b7fa0bb154fa9f28eb840da5c447baeb8d7e",
        strip_prefix = "rand-0.8.3",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.rand-0.8.3.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__rand_chacha__0_2_2",
        url = "https://crates.io/api/v1/crates/rand_chacha/0.2.2/download",
        type = "tar.gz",
        sha256 = "f4c8ed856279c9737206bf725bf36935d8666ead7aa69b52be55af369d193402",
        strip_prefix = "rand_chacha-0.2.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.rand_chacha-0.2.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__rand_chacha__0_3_0",
        url = "https://crates.io/api/v1/crates/rand_chacha/0.3.0/download",
        type = "tar.gz",
        sha256 = "e12735cf05c9e10bf21534da50a147b924d555dc7a547c42e6bb2d5b6017ae0d",
        strip_prefix = "rand_chacha-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.rand_chacha-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__rand_core__0_5_1",
        url = "https://crates.io/api/v1/crates/rand_core/0.5.1/download",
        type = "tar.gz",
        sha256 = "90bde5296fc891b0cef12a6d03ddccc162ce7b2aff54160af9338f8d40df6d19",
        strip_prefix = "rand_core-0.5.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.rand_core-0.5.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__rand_core__0_6_2",
        url = "https://crates.io/api/v1/crates/rand_core/0.6.2/download",
        type = "tar.gz",
        sha256 = "34cf66eb183df1c5876e2dcf6b13d57340741e8dc255b48e40a26de954d06ae7",
        strip_prefix = "rand_core-0.6.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.rand_core-0.6.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__rand_hc__0_2_0",
        url = "https://crates.io/api/v1/crates/rand_hc/0.2.0/download",
        type = "tar.gz",
        sha256 = "ca3129af7b92a17112d59ad498c6f81eaf463253766b90396d39ea7a39d6613c",
        strip_prefix = "rand_hc-0.2.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.rand_hc-0.2.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__rand_hc__0_3_0",
        url = "https://crates.io/api/v1/crates/rand_hc/0.3.0/download",
        type = "tar.gz",
        sha256 = "3190ef7066a446f2e7f42e239d161e905420ccab01eb967c9eb27d21b2322a73",
        strip_prefix = "rand_hc-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.rand_hc-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__rand_pcg__0_2_1",
        url = "https://crates.io/api/v1/crates/rand_pcg/0.2.1/download",
        type = "tar.gz",
        sha256 = "16abd0c1b639e9eb4d7c50c0b8100b0d0f849be2349829c740fe8e6eb4816429",
        strip_prefix = "rand_pcg-0.2.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.rand_pcg-0.2.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__redox_syscall__0_2_5",
        url = "https://crates.io/api/v1/crates/redox_syscall/0.2.5/download",
        type = "tar.gz",
        sha256 = "94341e4e44e24f6b591b59e47a8a027df12e008d73fd5672dbea9cc22f4507d9",
        strip_prefix = "redox_syscall-0.2.5",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.redox_syscall-0.2.5.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__remove_dir_all__0_5_3",
        url = "https://crates.io/api/v1/crates/remove_dir_all/0.5.3/download",
        type = "tar.gz",
        sha256 = "3acd125665422973a33ac9d3dd2df85edad0f4ae9b00dafb1a05e43a9f5ef8e7",
        strip_prefix = "remove_dir_all-0.5.3",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.remove_dir_all-0.5.3.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__ring__0_16_15",
        url = "https://crates.io/api/v1/crates/ring/0.16.15/download",
        type = "tar.gz",
        sha256 = "952cd6b98c85bbc30efa1ba5783b8abf12fec8b3287ffa52605b9432313e34e4",
        strip_prefix = "ring-0.16.15",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.ring-0.16.15.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__rustls__0_18_1",
        url = "https://crates.io/api/v1/crates/rustls/0.18.1/download",
        type = "tar.gz",
        sha256 = "5d1126dcf58e93cee7d098dbda643b5f92ed724f1f6a63007c1116eed6700c81",
        strip_prefix = "rustls-0.18.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.rustls-0.18.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__rustls_native_certs__0_4_0",
        url = "https://crates.io/api/v1/crates/rustls-native-certs/0.4.0/download",
        type = "tar.gz",
        sha256 = "629d439a7672da82dd955498445e496ee2096fe2117b9f796558a43fdb9e59b8",
        strip_prefix = "rustls-native-certs-0.4.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.rustls-native-certs-0.4.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__schannel__0_1_19",
        url = "https://crates.io/api/v1/crates/schannel/0.1.19/download",
        type = "tar.gz",
        sha256 = "8f05ba609c234e60bee0d547fe94a4c7e9da733d1c962cf6e59efa4cd9c8bc75",
        strip_prefix = "schannel-0.1.19",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.schannel-0.1.19.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__sct__0_6_0",
        url = "https://crates.io/api/v1/crates/sct/0.6.0/download",
        type = "tar.gz",
        sha256 = "e3042af939fca8c3453b7af0f1c66e533a15a86169e39de2657310ade8f98d3c",
        strip_prefix = "sct-0.6.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.sct-0.6.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__security_framework__1_0_0",
        url = "https://crates.io/api/v1/crates/security-framework/1.0.0/download",
        type = "tar.gz",
        sha256 = "ad502866817f0575705bd7be36e2b2535cc33262d493aa733a2ec862baa2bc2b",
        strip_prefix = "security-framework-1.0.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.security-framework-1.0.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__security_framework_sys__1_0_0",
        url = "https://crates.io/api/v1/crates/security-framework-sys/1.0.0/download",
        type = "tar.gz",
        sha256 = "51ceb04988b17b6d1dcd555390fa822ca5637b4a14e1f5099f13d351bed4d6c7",
        strip_prefix = "security-framework-sys-1.0.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.security-framework-sys-1.0.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__slab__0_4_2",
        url = "https://crates.io/api/v1/crates/slab/0.4.2/download",
        type = "tar.gz",
        sha256 = "c111b5bd5695e56cffe5129854aa230b39c93a305372fdbb2668ca2394eea9f8",
        strip_prefix = "slab-0.4.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.slab-0.4.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__socket2__0_3_19",
        url = "https://crates.io/api/v1/crates/socket2/0.3.19/download",
        type = "tar.gz",
        sha256 = "122e570113d28d773067fab24266b66753f6ea915758651696b6e35e49f88d6e",
        strip_prefix = "socket2-0.3.19",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.socket2-0.3.19.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__spin__0_5_2",
        url = "https://crates.io/api/v1/crates/spin/0.5.2/download",
        type = "tar.gz",
        sha256 = "6e63cff320ae2c57904679ba7cb63280a3dc4613885beafb148ee7bf9aa9042d",
        strip_prefix = "spin-0.5.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.spin-0.5.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__structopt__0_3_13",
        url = "https://crates.io/api/v1/crates/structopt/0.3.13/download",
        type = "tar.gz",
        sha256 = "ff6da2e8d107dfd7b74df5ef4d205c6aebee0706c647f6bc6a2d5789905c00fb",
        strip_prefix = "structopt-0.3.13",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.structopt-0.3.13.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__structopt_derive__0_4_6",
        url = "https://crates.io/api/v1/crates/structopt-derive/0.4.6/download",
        type = "tar.gz",
        sha256 = "a489c87c08fbaf12e386665109dd13470dcc9c4583ea3e10dd2b4523e5ebd9ac",
        strip_prefix = "structopt-derive-0.4.6",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.structopt-derive-0.4.6.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__syn__1_0_31",
        url = "https://crates.io/api/v1/crates/syn/1.0.31/download",
        type = "tar.gz",
        sha256 = "b5304cfdf27365b7585c25d4af91b35016ed21ef88f17ced89c7093b43dba8b6",
        strip_prefix = "syn-1.0.31",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.syn-1.0.31.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__syn_mid__0_5_0",
        url = "https://crates.io/api/v1/crates/syn-mid/0.5.0/download",
        type = "tar.gz",
        sha256 = "7be3539f6c128a931cf19dcee741c1af532c7fd387baa739c03dd2e96479338a",
        strip_prefix = "syn-mid-0.5.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.syn-mid-0.5.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tempfile__3_2_0",
        url = "https://crates.io/api/v1/crates/tempfile/3.2.0/download",
        type = "tar.gz",
        sha256 = "dac1c663cfc93810f88aed9b8941d48cabf856a1b111c29a40439018d870eb22",
        strip_prefix = "tempfile-3.2.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tempfile-3.2.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__textwrap__0_11_0",
        url = "https://crates.io/api/v1/crates/textwrap/0.11.0/download",
        type = "tar.gz",
        sha256 = "d326610f408c7a4eb6f51c37c330e496b08506c9457c9d34287ecc38809fb060",
        strip_prefix = "textwrap-0.11.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.textwrap-0.11.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__thiserror__1_0_18",
        url = "https://crates.io/api/v1/crates/thiserror/1.0.18/download",
        type = "tar.gz",
        sha256 = "5976891d6950b4f68477850b5b9e5aa64d955961466f9e174363f573e54e8ca7",
        strip_prefix = "thiserror-1.0.18",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.thiserror-1.0.18.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__thiserror_impl__1_0_18",
        url = "https://crates.io/api/v1/crates/thiserror-impl/1.0.18/download",
        type = "tar.gz",
        sha256 = "ab81dbd1cd69cd2ce22ecfbdd3bdb73334ba25350649408cc6c085f46d89573d",
        strip_prefix = "thiserror-impl-1.0.18",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.thiserror-impl-1.0.18.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__time__0_1_43",
        url = "https://crates.io/api/v1/crates/time/0.1.43/download",
        type = "tar.gz",
        sha256 = "ca8a50ef2360fbd1eeb0ecd46795a87a19024eb4b53c5dc916ca1fd95fe62438",
        strip_prefix = "time-0.1.43",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.time-0.1.43.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tokio__0_2_25",
        url = "https://crates.io/api/v1/crates/tokio/0.2.25/download",
        type = "tar.gz",
        sha256 = "6703a273949a90131b290be1fe7b039d0fc884aa1935860dfcbe056f28cd8092",
        strip_prefix = "tokio-0.2.25",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tokio-0.2.25.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tokio_rustls__0_14_1",
        url = "https://crates.io/api/v1/crates/tokio-rustls/0.14.1/download",
        type = "tar.gz",
        sha256 = "e12831b255bcfa39dc0436b01e19fea231a37db570686c06ee72c423479f889a",
        strip_prefix = "tokio-rustls-0.14.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tokio-rustls-0.14.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tokio_util__0_3_1",
        url = "https://crates.io/api/v1/crates/tokio-util/0.3.1/download",
        type = "tar.gz",
        sha256 = "be8242891f2b6cbef26a2d7e8605133c2c554cd35b3e4948ea892d6d68436499",
        strip_prefix = "tokio-util-0.3.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tokio-util-0.3.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tonic__0_3_0",
        url = "https://crates.io/api/v1/crates/tonic/0.3.0/download",
        type = "tar.gz",
        sha256 = "b13b102a19758191af97cff34c6785dffd6610f68de5ab1c4bb8378638e4ef90",
        strip_prefix = "tonic-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tonic-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tonic_build__0_3_0",
        url = "https://crates.io/api/v1/crates/tonic-build/0.3.0/download",
        type = "tar.gz",
        sha256 = "daec8b14e55497072204b53d5c0b1eb0a6ad1cd8301d6d4c079d4aeec35b21e9",
        strip_prefix = "tonic-build-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tonic-build-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower__0_3_1",
        url = "https://crates.io/api/v1/crates/tower/0.3.1/download",
        type = "tar.gz",
        sha256 = "fd3169017c090b7a28fce80abaad0ab4f5566423677c9331bb320af7e49cfe62",
        strip_prefix = "tower-0.3.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-0.3.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_balance__0_3_0",
        url = "https://crates.io/api/v1/crates/tower-balance/0.3.0/download",
        type = "tar.gz",
        sha256 = "a792277613b7052448851efcf98a2c433e6f1d01460832dc60bef676bc275d4c",
        strip_prefix = "tower-balance-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-balance-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_buffer__0_3_0",
        url = "https://crates.io/api/v1/crates/tower-buffer/0.3.0/download",
        type = "tar.gz",
        sha256 = "c4887dc2a65d464c8b9b66e0e4d51c2fd6cf5b3373afc72805b0a60bce00446a",
        strip_prefix = "tower-buffer-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-buffer-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_discover__0_3_0",
        url = "https://crates.io/api/v1/crates/tower-discover/0.3.0/download",
        type = "tar.gz",
        sha256 = "0f6b5000c3c54d269cc695dff28136bb33d08cbf1df2c48129e143ab65bf3c2a",
        strip_prefix = "tower-discover-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-discover-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_layer__0_3_1",
        url = "https://crates.io/api/v1/crates/tower-layer/0.3.1/download",
        type = "tar.gz",
        sha256 = "343bc9466d3fe6b0f960ef45960509f84480bf4fd96f92901afe7ff3df9d3a62",
        strip_prefix = "tower-layer-0.3.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-layer-0.3.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_limit__0_3_1",
        url = "https://crates.io/api/v1/crates/tower-limit/0.3.1/download",
        type = "tar.gz",
        sha256 = "92c3040c5dbed68abffaa0d4517ac1a454cd741044f33ab0eefab6b8d1361404",
        strip_prefix = "tower-limit-0.3.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-limit-0.3.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_load__0_3_0",
        url = "https://crates.io/api/v1/crates/tower-load/0.3.0/download",
        type = "tar.gz",
        sha256 = "8cc79fc3afd07492b7966d7efa7c6c50f8ed58d768a6075dd7ae6591c5d2017b",
        strip_prefix = "tower-load-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-load-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_load_shed__0_3_0",
        url = "https://crates.io/api/v1/crates/tower-load-shed/0.3.0/download",
        type = "tar.gz",
        sha256 = "9f021e23900173dc315feb4b6922510dae3e79c689b74c089112066c11f0ae4e",
        strip_prefix = "tower-load-shed-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-load-shed-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_make__0_3_0",
        url = "https://crates.io/api/v1/crates/tower-make/0.3.0/download",
        type = "tar.gz",
        sha256 = "ce50370d644a0364bf4877ffd4f76404156a248d104e2cc234cd391ea5cdc965",
        strip_prefix = "tower-make-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-make-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_ready_cache__0_3_1",
        url = "https://crates.io/api/v1/crates/tower-ready-cache/0.3.1/download",
        type = "tar.gz",
        sha256 = "4eabb6620e5481267e2ec832c780b31cad0c15dcb14ed825df5076b26b591e1f",
        strip_prefix = "tower-ready-cache-0.3.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-ready-cache-0.3.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_retry__0_3_0",
        url = "https://crates.io/api/v1/crates/tower-retry/0.3.0/download",
        type = "tar.gz",
        sha256 = "e6727956aaa2f8957d4d9232b308fe8e4e65d99db30f42b225646e86c9b6a952",
        strip_prefix = "tower-retry-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-retry-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_service__0_3_1",
        url = "https://crates.io/api/v1/crates/tower-service/0.3.1/download",
        type = "tar.gz",
        sha256 = "360dfd1d6d30e05fda32ace2c8c70e9c0a9da713275777f5a4dbb8a1893930c6",
        strip_prefix = "tower-service-0.3.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-service-0.3.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_timeout__0_3_0",
        url = "https://crates.io/api/v1/crates/tower-timeout/0.3.0/download",
        type = "tar.gz",
        sha256 = "127b8924b357be938823eaaec0608c482d40add25609481027b96198b2e4b31e",
        strip_prefix = "tower-timeout-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-timeout-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tower_util__0_3_1",
        url = "https://crates.io/api/v1/crates/tower-util/0.3.1/download",
        type = "tar.gz",
        sha256 = "d1093c19826d33807c72511e68f73b4a0469a3f22c2bd5f7d5212178b4b89674",
        strip_prefix = "tower-util-0.3.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tower-util-0.3.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tracing__0_1_24",
        url = "https://crates.io/api/v1/crates/tracing/0.1.24/download",
        type = "tar.gz",
        sha256 = "f77d3842f76ca899ff2dbcf231c5c65813dea431301d6eb686279c15c4464f12",
        strip_prefix = "tracing-0.1.24",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tracing-0.1.24.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tracing_attributes__0_1_13",
        url = "https://crates.io/api/v1/crates/tracing-attributes/0.1.13/download",
        type = "tar.gz",
        sha256 = "a8a9bd1db7706f2373a190b0d067146caa39350c486f3d455b0e33b431f94c07",
        strip_prefix = "tracing-attributes-0.1.13",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tracing-attributes-0.1.13.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tracing_core__0_1_17",
        url = "https://crates.io/api/v1/crates/tracing-core/0.1.17/download",
        type = "tar.gz",
        sha256 = "f50de3927f93d202783f4513cda820ab47ef17f624b03c096e86ef00c67e6b5f",
        strip_prefix = "tracing-core-0.1.17",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tracing-core-0.1.17.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__tracing_futures__0_2_4",
        url = "https://crates.io/api/v1/crates/tracing-futures/0.2.4/download",
        type = "tar.gz",
        sha256 = "ab7bb6f14721aa00656086e9335d363c5c8747bae02ebe32ea2c7dece5689b4c",
        strip_prefix = "tracing-futures-0.2.4",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.tracing-futures-0.2.4.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__try_lock__0_2_3",
        url = "https://crates.io/api/v1/crates/try-lock/0.2.3/download",
        type = "tar.gz",
        sha256 = "59547bce71d9c38b83d9c0e92b6066c4253371f15005def0c30d9657f50c7642",
        strip_prefix = "try-lock-0.2.3",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.try-lock-0.2.3.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__unicode_segmentation__1_7_1",
        url = "https://crates.io/api/v1/crates/unicode-segmentation/1.7.1/download",
        type = "tar.gz",
        sha256 = "bb0d2e7be6ae3a5fa87eed5fb451aff96f2573d2694942e40543ae0bbe19c796",
        strip_prefix = "unicode-segmentation-1.7.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.unicode-segmentation-1.7.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__unicode_width__0_1_8",
        url = "https://crates.io/api/v1/crates/unicode-width/0.1.8/download",
        type = "tar.gz",
        sha256 = "9337591893a19b88d8d87f2cec1e73fad5cdfd10e5a6f349f498ad6ea2ffb1e3",
        strip_prefix = "unicode-width-0.1.8",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.unicode-width-0.1.8.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__unicode_xid__0_2_1",
        url = "https://crates.io/api/v1/crates/unicode-xid/0.2.1/download",
        type = "tar.gz",
        sha256 = "f7fe0bb3479651439c9112f72b6c505038574c9fbb575ed1bf3b797fa39dd564",
        strip_prefix = "unicode-xid-0.2.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.unicode-xid-0.2.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__untrusted__0_7_1",
        url = "https://crates.io/api/v1/crates/untrusted/0.7.1/download",
        type = "tar.gz",
        sha256 = "a156c684c91ea7d62626509bce3cb4e1d9ed5c4d978f7b4352658f96a4c26b4a",
        strip_prefix = "untrusted-0.7.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.untrusted-0.7.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__version_check__0_9_2",
        url = "https://crates.io/api/v1/crates/version_check/0.9.2/download",
        type = "tar.gz",
        sha256 = "b5a972e5669d67ba988ce3dc826706fb0a8b01471c088cb0b6110b805cc36aed",
        strip_prefix = "version_check-0.9.2",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.version_check-0.9.2.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__want__0_3_0",
        url = "https://crates.io/api/v1/crates/want/0.3.0/download",
        type = "tar.gz",
        sha256 = "1ce8a968cb1cd110d136ff8b819a556d6fb6d919363c61534f6860c7eb172ba0",
        strip_prefix = "want-0.3.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.want-0.3.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__wasi__0_10_2_wasi_snapshot_preview1",
        url = "https://crates.io/api/v1/crates/wasi/0.10.2+wasi-snapshot-preview1/download",
        type = "tar.gz",
        sha256 = "fd6fbd9a79829dd1ad0cc20627bf1ed606756a7f77edff7b66b7064f9cb327c6",
        strip_prefix = "wasi-0.10.2+wasi-snapshot-preview1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.wasi-0.10.2+wasi-snapshot-preview1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__wasi__0_9_0_wasi_snapshot_preview1",
        url = "https://crates.io/api/v1/crates/wasi/0.9.0+wasi-snapshot-preview1/download",
        type = "tar.gz",
        sha256 = "cccddf32554fecc6acb585f82a32a72e28b48f8c4c1883ddfeeeaa96f7d8e519",
        strip_prefix = "wasi-0.9.0+wasi-snapshot-preview1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.wasi-0.9.0+wasi-snapshot-preview1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__wasm_bindgen__0_2_70",
        url = "https://crates.io/api/v1/crates/wasm-bindgen/0.2.70/download",
        type = "tar.gz",
        sha256 = "55c0f7123de74f0dab9b7d00fd614e7b19349cd1e2f5252bbe9b1754b59433be",
        strip_prefix = "wasm-bindgen-0.2.70",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.wasm-bindgen-0.2.70.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__wasm_bindgen_backend__0_2_70",
        url = "https://crates.io/api/v1/crates/wasm-bindgen-backend/0.2.70/download",
        type = "tar.gz",
        sha256 = "7bc45447f0d4573f3d65720f636bbcc3dd6ce920ed704670118650bcd47764c7",
        strip_prefix = "wasm-bindgen-backend-0.2.70",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.wasm-bindgen-backend-0.2.70.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__wasm_bindgen_macro__0_2_70",
        url = "https://crates.io/api/v1/crates/wasm-bindgen-macro/0.2.70/download",
        type = "tar.gz",
        sha256 = "3b8853882eef39593ad4174dd26fc9865a64e84026d223f63bb2c42affcbba2c",
        strip_prefix = "wasm-bindgen-macro-0.2.70",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.wasm-bindgen-macro-0.2.70.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__wasm_bindgen_macro_support__0_2_70",
        url = "https://crates.io/api/v1/crates/wasm-bindgen-macro-support/0.2.70/download",
        type = "tar.gz",
        sha256 = "4133b5e7f2a531fa413b3a1695e925038a05a71cf67e87dafa295cb645a01385",
        strip_prefix = "wasm-bindgen-macro-support-0.2.70",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.wasm-bindgen-macro-support-0.2.70.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__wasm_bindgen_shared__0_2_70",
        url = "https://crates.io/api/v1/crates/wasm-bindgen-shared/0.2.70/download",
        type = "tar.gz",
        sha256 = "dd4945e4943ae02d15c13962b38a5b1e81eadd4b71214eee75af64a4d6a4fd64",
        strip_prefix = "wasm-bindgen-shared-0.2.70",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.wasm-bindgen-shared-0.2.70.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__web_sys__0_3_47",
        url = "https://crates.io/api/v1/crates/web-sys/0.3.47/download",
        type = "tar.gz",
        sha256 = "c40dc691fc48003eba817c38da7113c15698142da971298003cac3ef175680b3",
        strip_prefix = "web-sys-0.3.47",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.web-sys-0.3.47.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__webpki__0_21_3",
        url = "https://crates.io/api/v1/crates/webpki/0.21.3/download",
        type = "tar.gz",
        sha256 = "ab146130f5f790d45f82aeeb09e55a256573373ec64409fc19a6fb82fb1032ae",
        strip_prefix = "webpki-0.21.3",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.webpki-0.21.3.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__which__3_1_1",
        url = "https://crates.io/api/v1/crates/which/3.1.1/download",
        type = "tar.gz",
        sha256 = "d011071ae14a2f6671d0b74080ae0cd8ebf3a6f8c9589a2cd45f23126fe29724",
        strip_prefix = "which-3.1.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.which-3.1.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__winapi__0_2_8",
        url = "https://crates.io/api/v1/crates/winapi/0.2.8/download",
        type = "tar.gz",
        sha256 = "167dc9d6949a9b857f3451275e911c3f44255842c1f7a76f33c55103a909087a",
        strip_prefix = "winapi-0.2.8",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.winapi-0.2.8.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__winapi__0_3_9",
        url = "https://crates.io/api/v1/crates/winapi/0.3.9/download",
        type = "tar.gz",
        sha256 = "5c839a674fcd7a98952e593242ea400abe93992746761e38641405d28b00f419",
        strip_prefix = "winapi-0.3.9",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.winapi-0.3.9.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__winapi_build__0_1_1",
        url = "https://crates.io/api/v1/crates/winapi-build/0.1.1/download",
        type = "tar.gz",
        sha256 = "2d315eee3b34aca4797b2da6b13ed88266e6d612562a0c46390af8299fc699bc",
        strip_prefix = "winapi-build-0.1.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.winapi-build-0.1.1.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__winapi_i686_pc_windows_gnu__0_4_0",
        url = "https://crates.io/api/v1/crates/winapi-i686-pc-windows-gnu/0.4.0/download",
        type = "tar.gz",
        sha256 = "ac3b87c63620426dd9b991e5ce0329eff545bccbbb34f3be09ff6fb6ab51b7b6",
        strip_prefix = "winapi-i686-pc-windows-gnu-0.4.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.winapi-i686-pc-windows-gnu-0.4.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__winapi_x86_64_pc_windows_gnu__0_4_0",
        url = "https://crates.io/api/v1/crates/winapi-x86_64-pc-windows-gnu/0.4.0/download",
        type = "tar.gz",
        sha256 = "712e227841d057c1ee1cd2fb22fa7e5a5461ae8e48fa2ca79ec42cfc1931183f",
        strip_prefix = "winapi-x86_64-pc-windows-gnu-0.4.0",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.winapi-x86_64-pc-windows-gnu-0.4.0.bazel"),
    )

    maybe(
        http_archive,
        name = "rules_rust_prostgen__ws2_32_sys__0_2_1",
        url = "https://crates.io/api/v1/crates/ws2_32-sys/0.2.1/download",
        type = "tar.gz",
        sha256 = "d59cefebd0c892fa2dd6de581e937301d8552cb44489cdff035c6187cb63fa5e",
        strip_prefix = "ws2_32-sys-0.2.1",
        build_file = Label("//proto/prostgen/raze/remote:BUILD.ws2_32-sys-0.2.1.bazel"),
    )
