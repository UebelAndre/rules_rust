/// An uninstrumented crate between the archive and `instrumented_dep`.
pub fn value() -> u32 {
    instrumented_dep::value()
}
