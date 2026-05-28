mod worker;
mod cache;

use std::process::exit;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.iter().any(|a| a == "--persistent_worker") {
        // The worker startup args contain the constant process_wrapper flags
        // (e.g. --subst pwd=${pwd}) and end with `-- <rustc-path>`. Bazel
        // sends only the per-action flags (the contents of the rustc param
        // file) in each WorkRequest.arguments. We strip `--persistent_worker`
        // from the startup args before stashing them.
        let startup_args: Vec<String> = args
            .into_iter()
            .filter(|a| a != "--persistent_worker")
            .collect();
        if let Err(e) = worker::run_worker_loop(startup_args) {
            eprintln!("Worker error: {}", e);
            exit(1);
        }
    } else {
        eprintln!("rustc_worker: must be invoked with --persistent_worker");
        exit(1);
    }
}
