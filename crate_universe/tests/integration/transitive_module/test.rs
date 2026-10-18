//! Crates from the hubs of dependency modules build and link alongside this
//! module's own, whether the dependency shipped a lockfile, none, or one this
//! version of rules_rust cannot read, and whether its archive was fetched or not.

lazy_static::lazy_static! {
    static ref ROOT: &'static str = "root";
}

#[test]
fn dependency_module_crates_resolve() {
    assert_eq!(*ROOT, "root");
    assert_eq!(dep_locked::name(), "dep_locked");
    assert_eq!(dep_unlocked_specs::name(), "dep_unlocked_specs");
    assert_eq!(dep_unlocked_cargo::name(), "dep_unlocked_cargo");
    assert_eq!(dep_unreadable::name(), "dep_unreadable");
    cfg_if::cfg_if! {
        if #[cfg(any())] {
            unreachable!();
        } else {
            assert!(true, "a crate from a module whose archive was never fetched");
        }
    }
}
