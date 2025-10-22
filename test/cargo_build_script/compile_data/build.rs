use std::env;
use std::path::PathBuf;

fn main() {
    let path = "data.txt";
    if !PathBuf::from(path).exists() {
        panic!("File does not exist in path.");
    }
    println!("cargo:rustc-env=DATA={}", path);

    // Note that absolute paths are required for the appropriate replacements.
    let cwd = env::current_dir().expect("Failed to access current working directory");
    let path = cwd.join("generated_data.txt");
    if !path.exists() {
        panic!("File does not exist in path.");
    }
    println!("cargo:rustc-env=GENERATED_DATA={}", path.display());

    let out_dir = std::env::var("OUT_DIR").expect("OUT_DIR not set");
    let out_file = PathBuf::from(out_dir).join("build_rs_data.txt");
    std::fs::write(out_file, "La-Li-Lu-Le-Lo\n").expect("Failed to write to OUT_DIR");
}
