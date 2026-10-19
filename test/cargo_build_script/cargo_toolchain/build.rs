//! Checks the `CARGO` a build script is given.

use std::env;
use std::path::Path;

fn main() {
    let cargo = env::var("CARGO").expect("`cargo_build_script` sets `CARGO`");
    assert!(
        Path::new(&cargo).is_file(),
        "`CARGO` should name an existing file, got `{cargo}`"
    );

    // rules_rust registers Cargo for `@rules_rust//cargo:toolchain_type` from
    // a repository named after the host triple. A `cargo` from the
    // `rust_toolchain` would live in a `rust_*` repository instead.
    let host = env::var("HOST").expect("`cargo_build_script` sets `HOST`");
    let repository = format!("cargo_{host}_tools");
    assert!(
        cargo.contains(&repository),
        "`CARGO` should come from the `cargo_toolchain` repository `{repository}`, got `{cargo}`"
    );

    println!("cargo:rustc-env=CARGO_FROM_BUILD_SCRIPT={cargo}");
}
