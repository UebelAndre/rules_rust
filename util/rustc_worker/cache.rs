use std::collections::HashMap;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::PathBuf;

pub struct IncrementalCache {
    cache_root: PathBuf,
    entries: HashMap<u64, PathBuf>,
    access_order: Vec<u64>,
    max_entries: usize,
}

impl IncrementalCache {
    pub fn new() -> Self {
        let cache_root = std::env::var("RULES_RUST_INCREMENTAL_CACHE_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                std::env::temp_dir().join("rules_rust_incremental")
            });

        IncrementalCache {
            cache_root,
            entries: HashMap::new(),
            access_order: Vec::new(),
            max_entries: 256,
        }
    }

    pub fn get_or_create(&mut self, args: &[String]) -> Option<PathBuf> {
        let key = Self::compute_key(args);
        self.touch(key);

        if let Some(path) = self.entries.get(&key) {
            return Some(path.clone());
        }

        self.evict_if_needed();

        let dir = self.cache_root.join(format!("{:016x}", key));
        if let Err(e) = std::fs::create_dir_all(&dir) {
            eprintln!("[worker] Failed to create incremental cache dir {}: {}", dir.display(), e);
            return None;
        }

        if std::env::var_os("RULES_RUST_WORKER_DEBUG").is_some() {
            eprintln!("[worker] cache dir: {}", dir.display());
        }

        self.entries.insert(key, dir.clone());
        Some(dir)
    }

    pub fn invalidate(&mut self, args: &[String]) {
        let key = Self::compute_key(args);
        if let Some(path) = self.entries.remove(&key) {
            let _ = std::fs::remove_dir_all(&path);
        }
        self.access_order.retain(|k| *k != key);
    }

    fn compute_key(args: &[String]) -> u64 {
        let mut hasher = DefaultHasher::new();
        for arg in args {
            arg.hash(&mut hasher);
        }
        hasher.finish()
    }

    fn touch(&mut self, key: u64) {
        self.access_order.retain(|k| *k != key);
        self.access_order.push(key);
    }

    fn evict_if_needed(&mut self) {
        while self.entries.len() >= self.max_entries {
            if let Some(oldest_key) = self.access_order.first().copied() {
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
