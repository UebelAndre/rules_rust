use std::collections::HashMap;
use std::path::PathBuf;

use sha2::{Digest, Sha256};

pub struct IncrementalCache {
    cache_root: PathBuf,
    entries: HashMap<String, PathBuf>,
    access_order: Vec<String>,
    max_entries: usize,
}

impl IncrementalCache {
    pub fn new() -> Self {
        let cache_root = std::env::var("RULES_RUST_INCREMENTAL_CACHE_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| std::env::temp_dir().join("rules_rust_incremental"));

        IncrementalCache {
            cache_root,
            entries: HashMap::new(),
            access_order: Vec::new(),
            max_entries: 256,
        }
    }

    pub fn get_or_create(&mut self, args: &[String]) -> Option<PathBuf> {
        let key = compute_cache_key(args)?;
        self.touch(&key);

        if let Some(path) = self.entries.get(&key) {
            return Some(path.clone());
        }

        self.evict_if_needed();

        let dir = self.cache_root.join(&key);
        if let Err(e) = std::fs::create_dir_all(&dir) {
            eprintln!(
                "[worker] Failed to create incremental cache dir {}: {}",
                dir.display(),
                e
            );
            return None;
        }

        if std::env::var_os("RULES_RUST_WORKER_DEBUG").is_some() {
            eprintln!("[worker] cache dir: {}", dir.display());
        }

        self.entries.insert(key, dir.clone());
        Some(dir)
    }

    pub fn invalidate(&mut self, args: &[String]) {
        if let Some(key) = compute_cache_key(args) {
            if let Some(path) = self.entries.remove(&key) {
                let _ = std::fs::remove_dir_all(&path);
            }
            self.access_order.retain(|k| k != &key);
        }
    }

    fn touch(&mut self, key: &str) {
        self.access_order.retain(|k| k != key);
        self.access_order.push(key.to_string());
    }

    fn evict_if_needed(&mut self) {
        while self.entries.len() >= self.max_entries {
            if let Some(oldest_key) = self.access_order.first().cloned() {
                self.access_order.remove(0);
                if let Some(path) = self.entries.remove(&oldest_key) {
                    let _ = std::fs::remove_dir_all(&path);
                }
            } else {
                break;
            }
        }
    }
}

/// Derives a deterministic cache key from a rustc invocation's args. Keys must
/// be stable across worker process restarts so the on-disk incremental cache
/// from a prior build can be reused.
///
/// We key off the **crate identity** rather than the full argv: crate name,
/// crate type, edition, target, and the output dir/filename. These are the
/// fields that uniquely identify a "logical" rustc invocation. Other flags
/// (e.g. dep extern paths) can differ between builds without invalidating
/// the incremental cache — rustc's own dep-graph will detect real changes.
fn compute_cache_key(args: &[String]) -> Option<String> {
    let mut hasher = Sha256::new();
    let mut any = false;

    for arg in args {
        // Match the rustc flags that define crate identity.
        if let Some(rest) = arg.strip_prefix("--crate-name=") {
            hasher.update(b"crate-name=");
            hasher.update(rest.as_bytes());
            hasher.update(b"\0");
            any = true;
        } else if let Some(rest) = arg.strip_prefix("--crate-type=") {
            hasher.update(b"crate-type=");
            hasher.update(rest.as_bytes());
            hasher.update(b"\0");
            any = true;
        } else if let Some(rest) = arg.strip_prefix("--edition=") {
            hasher.update(b"edition=");
            hasher.update(rest.as_bytes());
            hasher.update(b"\0");
            any = true;
        } else if let Some(rest) = arg.strip_prefix("--target=") {
            hasher.update(b"target=");
            hasher.update(rest.as_bytes());
            hasher.update(b"\0");
            any = true;
        } else if let Some(rest) = arg.strip_prefix("--out-dir=") {
            hasher.update(b"out-dir=");
            hasher.update(rest.as_bytes());
            hasher.update(b"\0");
            any = true;
        } else if let Some(rest) = arg.strip_prefix("--codegen=metadata=") {
            // Bazel-specific suffix used to disambiguate same-named crates.
            hasher.update(b"metadata=");
            hasher.update(rest.as_bytes());
            hasher.update(b"\0");
            any = true;
        }
    }

    if !any {
        return None;
    }

    let digest = hasher.finalize();
    let mut out = String::with_capacity(32);
    for byte in &digest[..16] {
        out.push_str(&format!("{:02x}", byte));
    }
    Some(out)
}
// rebuild
