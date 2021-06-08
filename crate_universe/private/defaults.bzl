"""A module defining generated information about crate_universe dependencies"""

# This global should match the current release of `crate_unvierse`.
DEFAULT_URL_TEMPLATE = "https://github.com/UebelAndre/rules_rust/releases/download/0.0.13/crate_universe_resolver-{host_triple}{extension}"

# Note that if any additional platforms are added here, the pipeline defined
# by `pre-release.yaml` should also be updated. The current shas are from
# release canddidate 1
DEFAULT_SHA256_CHECKSUMS = {
    "aarch64-apple-darwin": "d32c05e812e3a45f6d331aac5faf24900424b2b50b852f935456aeb136dd3755",
    "aarch64-unknown-linux-gnu": "069c31a96f2aeac96936b5afdca64e823c9088a1a8cd1c30d280915a94672ad3",
    "x86_64-apple-darwin": "ae9e988d4a5188a914d765453185a68a50806d4affe926ee924b1074e6affae3",
    "x86_64-pc-windows-gnu": "740a479dca3dd957c02ea5326031dff8936afe817c04ce201cf4babb4923a2cc",
    "x86_64-unknown-linux-gnu": "fea529e59c2391378f7ecc0df2f8eac251903f543483a2f229b63fc702d315d7",
}
