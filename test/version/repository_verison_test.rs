//! A test to ensure the bzlmod version matches the repository version

fn main() {
    // read MODULE.bazel
    let runfiles = runfiles::Runfiles::create().unwrap();
    let path = runfiles.rlocation(concat!("rules_rust/", env!("MODULE_BAZEL_ROOTPATH")));
    let content = std::fs::read_to_string(path).unwrap();

    // Render the template
    let def = format!(
        r#"
module(
    name = "rules_rust",
    version = "{}",
)
"#,
        env!("REPO_VERSION")
    );

    // ensure string is in text
    if !content.contains(&def) {
        eprintln!("MODULE.bazel appears to have an oudated module definition.");
        eprintln!("Please ensure the following content is in the file.");
        eprintln!("{}", def);
        std::process::exit(1);
    }
}
