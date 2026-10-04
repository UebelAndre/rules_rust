/// Bundles `instrumented_dep` into the archive handed to C/C++ consumers.
#[no_mangle]
pub extern "C" fn rules_rust_coverage_staticlib_with_dep() -> u32 {
    instrumented_dep::value()
}
