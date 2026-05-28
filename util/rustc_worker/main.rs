mod worker;
mod cache;

use std::process::exit;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.iter().any(|a| a == "--persistent_worker") {
        if let Err(e) = worker::run_worker_loop() {
            eprintln!("Worker error: {}", e);
            exit(1);
        }
    } else {
        eprintln!("rustc_worker: must be invoked with --persistent_worker");
        exit(1);
    }
}
