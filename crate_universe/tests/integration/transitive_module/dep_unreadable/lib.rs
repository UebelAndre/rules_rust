//! A library of a dependency module whose shipped lockfile its consumer could
//! not read, built against the hub the consumer resolved instead.

pub fn name() -> &'static str {
    cfg_if::cfg_if! {
        if #[cfg(any())] {
            "never"
        } else {
            "dep_unreadable"
        }
    }
}
