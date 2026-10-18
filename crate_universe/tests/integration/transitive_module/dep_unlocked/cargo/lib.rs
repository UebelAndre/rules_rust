//! A workspace member of a dependency module, built against a hub its consumer
//! resolved from the `Cargo.lock` shipped next to this manifest.

pub fn name() -> &'static str {
    cfg_if::cfg_if! {
        if #[cfg(any())] {
            "never"
        } else {
            "dep_unlocked_cargo"
        }
    }
}
