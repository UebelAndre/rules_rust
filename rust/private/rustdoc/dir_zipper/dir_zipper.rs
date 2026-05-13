use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use zip::write::SimpleFileOptions;
use zip::CompressionMethod;
use zip::ZipWriter;

const USAGE: &str = r#"usage: dir_zipper <output> <root-dir> [<file>...]

Creates a zip archive (store, no compression), stripping a directory prefix
from each file name.

Args:
  output:   Path to zip file to create.
  root_dir: Directory to strip from each archive name (no trailing slash).
  files:    List of files to include, all under root_dir.
"#;

fn run() -> io::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() < 2 {
        eprintln!("{}", USAGE);
        std::process::exit(1);
    }
    let output = Path::new(&args[0]);
    let root_dir = Path::new(&args[1]);
    let files: Vec<PathBuf> = args[2..].iter().map(PathBuf::from).collect();

    let out_file = fs::File::create(output)?;
    let mut zip = ZipWriter::new(out_file);
    let options = SimpleFileOptions::default().compression_method(CompressionMethod::Stored);

    for file in &files {
        let rel = file.strip_prefix(root_dir).map_err(|_| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                format!(
                    "non-descendant: {} not under {}",
                    file.display(),
                    root_dir.display()
                ),
            )
        })?;
        let name = rel.to_string_lossy();
        zip.start_file(name.as_ref(), options)?;
        let data = fs::read(file)?;
        zip.write_all(&data)?;
    }

    zip.finish()?;
    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("fatal: {}", e);
        std::process::exit(1);
    }
}
