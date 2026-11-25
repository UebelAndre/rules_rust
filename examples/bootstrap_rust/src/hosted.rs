//! A program for the host, against the standard library this example
//! compiled: it allocates, formats, spawns a thread and catches a panic,
//! each of which reaches a different part of `std`.

use std::collections::HashMap;
use std::panic;
use std::thread;

fn word_counts(text: &str) -> HashMap<&str, usize> {
    let mut counts = HashMap::new();
    for word in text.split_whitespace() {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

fn main() {
    let counts = word_counts("a standard library built from source, from source");
    println!("{} distinct words", counts.len());

    let handle = thread::spawn(|| (1..=10u64).product::<u64>());
    println!("10! = {}", handle.join().expect("the thread completes"));

    let caught = panic::catch_unwind(|| panic!("unwinding works"));
    println!("caught a panic: {}", caught.is_err());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_words() {
        let counts = word_counts("from source, from source");
        assert_eq!(counts["from"], 2);
        assert_eq!(counts["source,"], 1);
    }

    #[test]
    fn unwinds() {
        assert!(panic::catch_unwind(|| panic!("unwinding works")).is_err());
    }

    #[test]
    fn threads() {
        assert_eq!(thread::spawn(|| 6 * 7).join().unwrap(), 42);
    }
}
