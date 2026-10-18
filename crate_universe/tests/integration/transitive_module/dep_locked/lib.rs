//! A library of a dependency module, built against its own crate_universe hub.

pub fn name() -> &'static str {
    cfg_if::cfg_if! {
        if #[cfg(any())] {
            "never"
        } else {
            "dep_locked"
        }
    }
}
