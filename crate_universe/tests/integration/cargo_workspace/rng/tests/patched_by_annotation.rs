//! `rand` is patched by a `crate.annotation` of this module; see `MODULE.bazel`.

#[test]
fn rand_is_patched() {
    assert!(rand::patched_by_annotation());
}
