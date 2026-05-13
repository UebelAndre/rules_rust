use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const USAGE: &str = r#"usage: doc_merger --output-dir <dir> [--doc-dir <dir>]... -- <command> [<args>...]

Runs a rustdoc finalize command, then copies per-crate doc directories into
the output.

Args:
  --output-dir: The output directory for the merged documentation.
  --doc-dir:    A per-crate documentation directory to copy into the output
                (repeatable).
  --:           Separator. Everything after this is the rustdoc command to run.
"#;

macro_rules! die {
    ($($arg:tt)*) => {{
        eprintln!($($arg)*);
        std::process::exit(1);
    }};
}

fn copy_dir_recursive(src: &Path, dst: &Path) {
    if !dst.exists() {
        fs::create_dir_all(dst).unwrap_or_else(|e| {
            die!("fatal: could not create directory {}: {}", dst.display(), e);
        });
    }
    for entry in fs::read_dir(src).unwrap_or_else(|e| {
        die!("fatal: could not read directory {}: {}", src.display(), e);
    }) {
        let entry = entry.unwrap_or_else(|e| {
            die!("fatal: could not read entry in {}: {}", src.display(), e);
        });
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if src_path.is_dir() {
            copy_dir_recursive(&src_path, &dst_path);
        } else {
            fs::copy(&src_path, &dst_path).unwrap_or_else(|e| {
                die!(
                    "fatal: could not copy {} to {}: {}",
                    src_path.display(),
                    dst_path.display(),
                    e
                );
            });
        }
    }
}

fn main() {
    let args: Vec<OsString> = std::env::args_os().skip(1).collect();

    let mut output_dir: Option<PathBuf> = None;
    let mut doc_dirs: Vec<PathBuf> = Vec::new();
    let mut command_start: Option<usize> = None;

    let mut i = 0;
    while i < args.len() {
        let arg = args[i].to_string_lossy();
        if arg == "--" {
            command_start = Some(i + 1);
            break;
        } else if arg == "--output-dir" {
            i += 1;
            output_dir = Some(PathBuf::from(&args[i]));
        } else if arg == "--doc-dir" {
            i += 1;
            doc_dirs.push(PathBuf::from(&args[i]));
        } else {
            die!("fatal: unknown argument: {}\n{}", arg, USAGE);
        }
        i += 1;
    }

    let output_dir = output_dir.unwrap_or_else(|| die!("fatal: --output-dir is required\n{}", USAGE));
    let command_start = command_start.unwrap_or_else(|| die!("fatal: missing -- separator\n{}", USAGE));
    if command_start >= args.len() {
        die!("fatal: no command specified after --\n{}", USAGE);
    }

    // Run the rustdoc finalize command
    let exit_status = Command::new(&args[command_start])
        .args(&args[command_start + 1..])
        .spawn()
        .unwrap_or_else(|e| die!("fatal: could not spawn command: {}", e))
        .wait()
        .unwrap_or_else(|e| die!("fatal: could not wait on command: {}", e));

    if !exit_status.success() {
        match exit_status.code() {
            Some(c) => std::process::exit(c),
            None => die!("fatal: command terminated by signal"),
        }
    }

    // Copy each doc dir's contents into the output directory
    for doc_dir in &doc_dirs {
        if doc_dir.exists() {
            copy_dir_recursive(doc_dir, &output_dir);
        }
    }
}
