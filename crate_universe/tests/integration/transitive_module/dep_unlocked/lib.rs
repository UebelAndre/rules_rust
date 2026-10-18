//! A library of a dependency module, built against a hub resolved by its consumer.

lazy_static::lazy_static! {
    static ref NAME: &'static str = "dep_unlocked_specs";
}

pub fn name() -> &'static str {
    &NAME
}
