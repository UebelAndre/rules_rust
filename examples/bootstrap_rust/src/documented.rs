//! A crate for rustdoc and Clippy built from source to work on.

/// Adds two numbers, documented so that rustdoc has something to render and
/// written so that Clippy has nothing to say.
///
/// ```
/// assert_eq!(documented::add(2, 2), 4);
/// ```
pub fn add(left: u64, right: u64) -> u64 {
    left + right
}
