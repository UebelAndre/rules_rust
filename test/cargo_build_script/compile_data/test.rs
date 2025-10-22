#[test]
pub fn test_data_propagation() {
    let data = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/", env!("DATA")));

    assert_eq!("La-Li-Lu-Le-Lo\n", data);
}

#[test]
pub fn test_out_dir() {
    let data = include_str!(concat!(env!("OUT_DIR"), "/build_rs_data.txt"));

    assert_eq!("La-Li-Lu-Le-Lo\n", data);
}
