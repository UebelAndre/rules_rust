/// A Rust `dylib`. `rustc` performs the final link, so it links the profile
/// runtime itself when instrumented.
pub fn rules_rust_coverage_dylib() -> u32 {
    1
}
