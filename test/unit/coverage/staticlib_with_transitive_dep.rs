/// Only a transitive dependency of this archive is instrumented.
#[no_mangle]
pub extern "C" fn rules_rust_coverage_staticlib_with_transitive_dep() -> u32 {
    middle::value()
}
