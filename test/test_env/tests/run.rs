#[test]
fn run() {
    let path = env!("CARGO_BIN_EXE_hello-world");
    let output = std::process::Command::new(path)
        .output()
        .expect("Failed to run process");
    assert_eq!(&b"Hello world\n"[..], output.stdout.as_slice());

    // Test the `env` attribute of `rust_test` at run time
    assert_eq!(
        std::env::var("FERRIS_SAYS").unwrap(),
        "Hello fellow Rustaceans!"
    );

    // Ensure environmnet variables set using `env` are also available at compile time
    assert_eq!(env!("FERRIS_SAYS"), "Hello fellow Rustaceans!");

    // Test the behavior of `rootpath` and that a binary can be found relative to current_dir
    let hello_world_bin =
        std::path::PathBuf::from(std::env::var_os("HELLO_WORLD_BIN_ROOTPATH").unwrap());

    assert_eq!(
        hello_world_bin.as_path(),
        std::path::Path::new(if std::env::consts::OS == "windows" {
            "test/test_env/hello-world.exe"
        } else {
            "test/test_env/hello-world"
        })
    );
    assert!(!hello_world_bin.is_absolute());
    assert!(hello_world_bin.exists());
}
