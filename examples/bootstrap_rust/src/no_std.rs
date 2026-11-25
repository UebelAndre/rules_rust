//! A program with no standard library, for the host: no `std`, no `main`,
//! no C runtime. It links `core`, `compiler_builtins` and `alloc` from the
//! standard library this example compiled, and nothing else. It exits with
//! the checksum it computes, which the test checks.

#![no_std]
#![no_main]

use core::panic::PanicInfo;

/// Where the kernel starts the program, since nothing links a C runtime in.
#[unsafe(no_mangle)]
pub extern "C" fn _start() -> ! {
    // `compiler_builtins` provides `memset` for a target without a C
    // library; filling a buffer makes sure it is linked in.
    let mut buffer = [0u8; 64];
    buffer.fill(0x5a);
    let checksum = buffer
        .iter()
        .fold(0u32, |sum, &byte| sum.wrapping_add(u32::from(byte)));
    exit((checksum % 256) as i32)
}

/// The `exit` system call, by hand: there is no `libc` to make it.
fn exit(code: i32) -> ! {
    // SAFETY: the system call takes the exit status and does not return.
    unsafe {
        #[cfg(target_arch = "x86_64")]
        core::arch::asm!("syscall", in("rax") 231usize, in("rdi") code as usize, options(noreturn));
        #[cfg(target_arch = "aarch64")]
        core::arch::asm!("svc #0", in("x8") 94usize, in("x0") code as usize, options(noreturn));
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    exit(1)
}
