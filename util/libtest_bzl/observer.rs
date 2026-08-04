//! In-process libtest observer.
//!
//! Activated from a pre-`main` constructor when `XML_OUTPUT_FILE` is set
//! (i.e. under `bazel test`). It redirects the process's stdout through a
//! pipe, spawns a thread that copies every byte to the real stdout unchanged
//! while feeding a line parser, and maintains a JUnit XML file incrementally
//! as results appear. A wrapping panic hook records panic messages keyed by
//! thread name (libtest names each test thread after the test) to enrich
//! failure entries when the failures section isn't printed (`--nocapture`).
//!
//! When `XML_OUTPUT_FILE` is not set — `bazel run`, debuggers, plain
//! execution — the constructor does nothing at all. `RULES_RUST_NO_JUNIT=1`
//! disables the observer even under `bazel test`.
//!
//! The XML file is rewritten after every parsed result, so a mid-suite crash
//! (including `panic = "abort"`) still leaves a valid document with every
//! test that completed before the crash. If nothing parseable was seen, no
//! file is written and Bazel's own fallback XML generation applies.

use std::collections::HashMap;
use std::io::Write as _;
use std::path::PathBuf;
use std::sync::{Condvar, Mutex, MutexGuard, OnceLock, PoisonError};
use std::time::{Duration, Instant};

use crate::junit;
use crate::parse::{Case, Outcome, Parser};

// Pre-`main` constructor. The parent module is already `#[cfg]`-gated to the
// platforms where these init tables are recognized (unix except emscripten,
// or windows), so no further gate is needed on the block itself — only on
// each per-flavor `link_section`.

extern "C" fn ctor_entry() {
    init();
}

#[cfg(all(target_family = "unix", not(target_vendor = "apple")))]
#[used]
#[link_section = ".init_array"]
static CTOR: extern "C" fn() = ctor_entry;

#[cfg(target_vendor = "apple")]
#[used]
#[link_section = "__DATA,__mod_init_func"]
static CTOR: extern "C" fn() = ctor_entry;

// Works for both windows-msvc and windows-gnu: the MSVC CRT runs `.CRT$XCU`
// entries directly, and mingw-w64's startup code processes the same
// MSVC-compatible init tables (`__xc_a`..`__xc_z`).
#[cfg(target_os = "windows")]
#[used]
#[link_section = ".CRT$XCU"]
static CTOR: extern "C" fn() = ctor_entry;

static STATE: OnceLock<State> = OnceLock::new();

struct State {
    xml_path: PathBuf,
    start: Instant,
    redirect: sys::Redirect,
    parser: Mutex<Parser>,
    /// Panic messages recorded by the hook, keyed by panicking thread name.
    panics: Mutex<HashMap<String, String>>,
    done: Mutex<bool>,
    done_cv: Condvar,
}

/// Entry point invoked by the pre-`main` constructor.
pub(crate) fn init() {
    // The observer must never take down the test process.
    let _ = std::panic::catch_unwind(init_inner);
}

fn init_inner() {
    if std::env::var_os("RULES_RUST_NO_JUNIT").is_some() {
        return;
    }
    let xml_path = match std::env::var_os("XML_OUTPUT_FILE") {
        Some(path) if !path.is_empty() => PathBuf::from(path),
        _ => return,
    };

    let Some(redirect) = (unsafe { sys::redirect() }) else {
        return;
    };

    let state = State {
        xml_path,
        start: Instant::now(),
        redirect,
        parser: Mutex::new(Parser::new()),
        panics: Mutex::new(HashMap::new()),
        done: Mutex::new(false),
        done_cv: Condvar::new(),
    };
    if STATE.set(state).is_err() {
        sys::restore(&redirect);
        return;
    }
    let state = STATE.get().expect("state was just set");

    install_panic_hook(state);
    unsafe {
        sys::atexit(finalize_at_exit);
    }

    let spawned = std::thread::Builder::new()
        .name("libtest_bzl_tee".to_string())
        .spawn(move || tee_loop(state));
    if spawned.is_err() {
        // Nobody will drain the pipe; put stdout back before anyone writes.
        sys::restore(&state.redirect);
    }
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

fn install_panic_hook(state: &'static State) {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let message = info
            .payload()
            .downcast_ref::<&'static str>()
            .map(|s| (*s).to_string())
            .or_else(|| info.payload().downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "<non-string panic payload>".to_string());
        let message = match info.location() {
            Some(location) => format!("panicked at {}: {}", location, message),
            None => message,
        };
        if let Some(name) = std::thread::current().name() {
            lock(&state.panics).insert(name.to_string(), message);
        }
        previous(info);
    }));
}

fn tee_loop(state: &'static State) {
    let mut buf = [0u8; 8192];
    let mut pending: Vec<u8> = Vec::new();
    loop {
        let n = sys::read_pipe(&state.redirect, &mut buf);
        if n == 0 {
            break;
        }
        sys::write_real(&state.redirect, &buf[..n]);
        pending.extend_from_slice(&buf[..n]);

        let mut changed = false;
        while let Some(pos) = pending.iter().position(|&b| b == b'\n') {
            // Scope the borrow of `pending` from `from_utf8_lossy` so `drain`
            // can mutate it below. ASCII output (the common case) returns a
            // borrowed `Cow`, so no per-line allocation.
            let changed_line = {
                let line = String::from_utf8_lossy(&pending[..pos]);
                lock(&state.parser).feed_line(&line)
            };
            pending.drain(..=pos);
            if changed_line {
                changed = true;
            }
        }
        if changed {
            write_xml(state);
        }
    }

    if !pending.is_empty() {
        let line = String::from_utf8_lossy(&pending).into_owned();
        lock(&state.parser).feed_line(&line);
    }
    lock(&state.parser).finish();
    write_xml(state);

    *lock(&state.done) = true;
    state.done_cv.notify_all();
}

/// Render the current model and (re)write the XML file. Idempotent; called
/// after every parsed result and again at finalization.
fn write_xml(state: &State) {
    let parser = lock(&state.parser);
    if !parser.has_data() {
        return;
    }
    let panics = lock(&state.panics);
    let elapsed = state.start.elapsed().as_secs_f64();
    let name = suite_name();
    let summary = parser.summary().copied();

    // Called after every parsed result: N calls, each seeing up to N cases,
    // so quadratic in test count. The common case is `panics.is_empty()`
    // (nothing panicked, or every failure already has a captured detail
    // block), so render directly from the parser's snapshot without any
    // clone. Only pay the per-case allocation when there is actually a
    // panic message to merge.
    let xml = if panics.is_empty() {
        junit::render(name, parser.cases(), summary.as_ref(), elapsed)
    } else {
        let cases: Vec<Case> = parser
            .cases()
            .iter()
            .map(|case| {
                if case.outcome == Outcome::Failed && case.detail.is_none() {
                    if let Some(msg) = panics.get(&case.name) {
                        let mut c = case.clone();
                        c.detail = Some(msg.clone());
                        return c;
                    }
                }
                case.clone()
            })
            .collect();
        junit::render(name, &cases, summary.as_ref(), elapsed)
    };
    drop(panics);
    drop(parser);
    let _ = std::fs::write(&state.xml_path, xml);
}

fn suite_name() -> &'static str {
    static SUITE_NAME: OnceLock<String> = OnceLock::new();
    SUITE_NAME.get_or_init(|| {
        std::env::args()
            .next()
            .map(PathBuf::from)
            .and_then(|path| {
                path.file_stem()
                    .map(|stem| stem.to_string_lossy().into_owned())
            })
            .filter(|stem| !stem.is_empty())
            .unwrap_or_else(|| "rust_test".to_string())
    })
}

extern "C" fn finalize_at_exit() {
    let Some(state) = STATE.get() else {
        return;
    };
    // Push any buffered output into the pipe for the parser, then point
    // stdout back at the real stream. Dropping the process's last write end
    // delivers EOF to the tee thread, which flushes the final XML.
    let _ = std::io::stdout().flush();
    sys::restore(&state.redirect);

    let done = lock(&state.done);
    let timeout = Duration::from_secs(5);
    let _ = state
        .done_cv
        .wait_timeout_while(done, timeout, |finished| !*finished);
    // Normally a no-op (the tee thread already wrote on EOF); covers the
    // timeout path where a child process inherited the pipe's write end.
    write_xml(state);
}

#[cfg(unix)]
mod sys {
    use std::os::raw::{c_int, c_void};

    const STDOUT_FILENO: c_int = 1;
    const F_SETFD: c_int = 2;
    const FD_CLOEXEC: c_int = 1;

    // The observer is linked whole-archive into a test binary that never
    // references it, so nothing else on the link line depends on libc for
    // *our* sake before the observer's own object appears. Explicit `#[link]`
    // ensures libc is marked NEEDED for the observer's symbol references
    // (chiefly `atexit`), independent of link-line ordering or `--as-needed`.
    #[link(name = "c", kind = "dylib")]
    extern "C" {
        fn pipe(fds: *mut c_int) -> c_int;
        fn dup(fd: c_int) -> c_int;
        fn dup2(src: c_int, dst: c_int) -> c_int;
        fn close(fd: c_int) -> c_int;
        fn read(fd: c_int, buf: *mut c_void, count: usize) -> isize;
        fn write(fd: c_int, buf: *const c_void, count: usize) -> isize;
        fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
        pub(super) fn atexit(cb: extern "C" fn()) -> c_int;
    }

    #[derive(Clone, Copy)]
    pub(super) struct Redirect {
        read_fd: c_int,
        real_stdout: c_int,
    }

    /// Point fd 1 at a fresh pipe, returning the pipe's read end and a
    /// duplicate of the original stdout.
    pub(super) unsafe fn redirect() -> Option<Redirect> {
        let mut fds = [0 as c_int; 2];
        if pipe(fds.as_mut_ptr()) != 0 {
            return None;
        }
        let (read_fd, write_fd) = (fds[0], fds[1]);
        let real_stdout = dup(STDOUT_FILENO);
        if real_stdout < 0 {
            close(read_fd);
            close(write_fd);
            return None;
        }
        // Keep observer-internal fds out of child processes spawned by
        // tests; only the pipe's write end (as fd 1) should be inherited.
        fcntl(read_fd, F_SETFD, FD_CLOEXEC);
        fcntl(real_stdout, F_SETFD, FD_CLOEXEC);
        if dup2(write_fd, STDOUT_FILENO) < 0 {
            close(read_fd);
            close(write_fd);
            close(real_stdout);
            return None;
        }
        close(write_fd);
        Some(Redirect {
            read_fd,
            real_stdout,
        })
    }

    /// Read from the pipe. Returns 0 on EOF or unrecoverable error.
    pub(super) fn read_pipe(redirect: &Redirect, buf: &mut [u8]) -> usize {
        loop {
            let n = unsafe { read(redirect.read_fd, buf.as_mut_ptr() as *mut c_void, buf.len()) };
            if n >= 0 {
                return n as usize;
            }
            if std::io::Error::last_os_error().kind() != std::io::ErrorKind::Interrupted {
                return 0;
            }
        }
    }

    /// Copy bytes to the saved real stdout, dropping them if it is gone.
    pub(super) fn write_real(redirect: &Redirect, mut buf: &[u8]) {
        while !buf.is_empty() {
            let n = unsafe {
                write(
                    redirect.real_stdout,
                    buf.as_ptr() as *const c_void,
                    buf.len(),
                )
            };
            if n > 0 {
                buf = &buf[n as usize..];
                continue;
            }
            if std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return;
        }
    }

    /// Point fd 1 back at the real stdout. The pipe's last in-process write
    /// end goes away with the dup2, delivering EOF to the tee thread.
    pub(super) fn restore(redirect: &Redirect) {
        unsafe {
            dup2(redirect.real_stdout, STDOUT_FILENO);
        }
    }
}

#[cfg(windows)]
mod sys {
    use std::ffi::c_void;
    use std::ptr::null_mut;

    type Handle = *mut c_void;

    const STD_OUTPUT_HANDLE: u32 = 0xFFFF_FFF5; // (DWORD)-11
    const INVALID_HANDLE_VALUE: isize = -1;

    #[link(name = "kernel32")]
    extern "system" {
        fn GetStdHandle(kind: u32) -> Handle;
        fn SetStdHandle(kind: u32, handle: Handle) -> i32;
        fn CreatePipe(
            read: *mut Handle,
            write: *mut Handle,
            attributes: *mut c_void,
            size: u32,
        ) -> i32;
        fn ReadFile(
            handle: Handle,
            buf: *mut u8,
            len: u32,
            bytes_read: *mut u32,
            overlapped: *mut c_void,
        ) -> i32;
        fn WriteFile(
            handle: Handle,
            buf: *const u8,
            len: u32,
            bytes_written: *mut u32,
            overlapped: *mut c_void,
        ) -> i32;
        fn CloseHandle(handle: Handle) -> i32;
    }

    // See the Unix `#[link(name = "c", ...)]` comment above. `msvcrt` is the
    // legacy dynamic CRT that provides `atexit` on both windows-msvc (unless
    // the target is explicitly UCRT) and windows-gnu.
    #[link(name = "msvcrt", kind = "dylib")]
    extern "C" {
        pub(super) fn atexit(cb: extern "C" fn()) -> i32;
    }

    // Raw handles stored as `usize` so the struct is `Send`/`Sync`.
    #[derive(Clone, Copy)]
    pub(super) struct Redirect {
        read_handle: usize,
        write_handle: usize,
        real_stdout: usize,
    }

    /// Replace the process's stdout std-handle with a fresh pipe.
    ///
    /// Note: the C runtime binds its fd 1 to the original handle before
    /// constructors run, so output from C code via `printf` bypasses the tee
    /// (it still reaches the user). Rust's std resolves the std handle per
    /// write, which is what libtest uses — the parser sees everything it
    /// needs.
    pub(super) unsafe fn redirect() -> Option<Redirect> {
        let real = GetStdHandle(STD_OUTPUT_HANDLE);
        if real.is_null() || real as isize == INVALID_HANDLE_VALUE {
            return None;
        }
        let mut read: Handle = null_mut();
        let mut write: Handle = null_mut();
        if CreatePipe(&mut read, &mut write, null_mut(), 0) == 0 {
            return None;
        }
        if SetStdHandle(STD_OUTPUT_HANDLE, write) == 0 {
            CloseHandle(read);
            CloseHandle(write);
            return None;
        }
        Some(Redirect {
            read_handle: read as usize,
            write_handle: write as usize,
            real_stdout: real as usize,
        })
    }

    /// Read from the pipe. Returns 0 on EOF (broken pipe) or error.
    pub(super) fn read_pipe(redirect: &Redirect, buf: &mut [u8]) -> usize {
        loop {
            let mut bytes_read: u32 = 0;
            let ok = unsafe {
                ReadFile(
                    redirect.read_handle as Handle,
                    buf.as_mut_ptr(),
                    buf.len().min(u32::MAX as usize) as u32,
                    &mut bytes_read,
                    null_mut(),
                )
            };
            if ok == 0 {
                // ERROR_BROKEN_PIPE: all write handles closed. Any other
                // error also ends the tee.
                return 0;
            }
            if bytes_read > 0 {
                return bytes_read as usize;
            }
        }
    }

    pub(super) fn write_real(redirect: &Redirect, mut buf: &[u8]) {
        while !buf.is_empty() {
            let mut written: u32 = 0;
            let ok = unsafe {
                WriteFile(
                    redirect.real_stdout as Handle,
                    buf.as_ptr(),
                    buf.len().min(u32::MAX as usize) as u32,
                    &mut written,
                    null_mut(),
                )
            };
            if ok == 0 || written == 0 {
                return;
            }
            buf = &buf[written as usize..];
        }
    }

    /// Point the stdout std-handle back at the real stream and close our
    /// write end, delivering EOF to the tee thread.
    pub(super) fn restore(redirect: &Redirect) {
        unsafe {
            SetStdHandle(STD_OUTPUT_HANDLE, redirect.real_stdout as Handle);
            CloseHandle(redirect.write_handle as Handle);
        }
    }
}
