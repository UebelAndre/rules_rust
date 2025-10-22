/// A test showing files are accessible relative to `CARGO_MANIFEST_DIR` at compile time.
#[test]
pub fn test_data_propagation() {
    let data = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/", env!("DATA")));

    assert_eq!("La-Li-Lu-Le-Lo\n", data);
}

/// A test showing execpaths referenced in build.rs produced environment variables
/// are correctly resolved to files in a separate action.
#[test]
pub fn test_generated_data_propagation() {
    let data = include_str!(env!("GENERATED_DATA"));

    assert_eq!("La-Li-Lu-Le-Lo\n", data);
}

/// A test showing files generated into `OUT_DIR` are available at compile time.
#[test]
pub fn test_out_dir() {
    let data = include_str!(concat!(env!("OUT_DIR"), "/build_rs_data.txt"));

    assert_eq!("La-Li-Lu-Le-Lo\n", data);
}
