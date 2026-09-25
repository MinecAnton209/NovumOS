// Common Utilities Module
// Provides shared logic for printing, system control, and file system access.

const fs = @import("../kernel/fs.zig");
const config = @import("../config.zig");
pub const vga = @import("../drivers/vga.zig");
const timer = @import("../drivers/timer.zig");
const acpi = @import("../drivers/acpi.zig");

const serial = @import("../drivers/serial.zig");
const logger = @import("../kernel/logger.zig");

const str_util = @import("../kernel/str.zig");
pub const std_mem_eql = str_util.std_mem_eql;
pub const startsWith = str_util.startsWith;
pub const endsWith = str_util.endsWith;
pub const asciiLower = str_util.asciiLower;
pub const startsWithIgnoreCase = str_util.startsWithIgnoreCase;
pub const lastIndexOf = str_util.lastIndexOf;
pub const copy = str_util.copy;
pub const math_abs = str_util.math_abs;
pub const math_max = str_util.math_max;
pub const math_min = str_util.math_min;

// Global State
pub var selected_disk: i8 = -1; // -1 means RAM FS
pub var current_dir_cluster: u32 = 0; // 0 = Root on FAT12/16
pub var current_path: [256]u8 = [_]u8{0} ** 256;
pub var current_path_len: usize = 0;

pub var redirect_active: bool = false;
pub var redirect_buffer: [32768]u8 = undefined;
pub var redirect_pos: usize = 0;

pub var pipe_active: bool = false;
pub var pipe_buffer: [16384]u8 = [_]u8{0} ** 16384;
pub var pipe_pos: usize = 0;
pub var pipe_read_active: bool = false;

/// True when running with Ring 3 privileges (user mode).
fn in_ring3() bool {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    return (cs & 3) == 3;
}

/// Issue a syscall from Ring 3 and return raw eax. Call only after in_ring3().
/// The int 0x80 stub pushad/popad's, so unused arg registers are harmless.
fn syscall_proxy(comptime num: u32, arg0: u32, arg1: u32, arg2: u32, arg3: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [sys] "{eax}" (@as(u32, num)),
          [b] "{ebx}" (arg0),
          [c] "{ecx}" (arg1),
          [d] "{edx}" (arg2),
          [s] "{esi}" (arg3),
    );
}

/// Low-level character output
pub fn print_char(c: u8) void {
    if (pipe_active) {
        if (pipe_pos < pipe_buffer.len) {
            pipe_buffer[pipe_pos] = c;
            pipe_pos += 1;
        }
        return;
    }
    if (redirect_active) {
        if (redirect_pos < redirect_buffer.len) {
            redirect_buffer[redirect_pos] = c;
            redirect_pos += 1;
        }
        return;
    }

    // Detect User Mode (Ring 3) by checking the low bits of Code Segment (CS)
    if (in_ring3()) {
        var buf: [2]u8 = .{ c, 0 };
        _ = syscall_proxy(1, @intFromPtr(&buf), 0, 0, 0);
        return;
    }

    vga.zig_print_char(c);
    serial.serial_print_char(c);
}

pub fn draw_char_at(row: u8, col: u8, c: u8, attr: u16) void {
    if (in_ring3()) {
        _ = syscall_proxy(18, row, col, c, attr); // 18: DrawCharAt
        return;
    }

    const old = vga.current_color;
    vga.current_color = attr;
    vga.zig_draw_char_at(row, col, c);
    vga.current_color = old;
}

pub fn get_char() u8 {
    if (in_ring3()) {
        return @intCast(syscall_proxy(2, 0, 0, 0, 0));
    }
    const keyboard = @import("../arch/mod.zig").keyboard_isr;
    return keyboard.keyboard_wait_char();
}

pub fn set_cursor(row: u8, col: u8) void {
    if (in_ring3()) {
        _ = syscall_proxy(3, row, col, 0, 0);
        return;
    }
    vga.zig_set_cursor(row, col);
}

pub fn get_cursor_row() u8 {
    if (in_ring3()) {
        return @intCast(syscall_proxy(4, 0, 0, 0, 0) >> 8);
    }
    return vga.zig_get_cursor_row();
}

pub fn get_cursor_col() u8 {
    if (in_ring3()) {
        return @intCast(syscall_proxy(4, 0, 0, 0, 0) & 0xFF);
    }
    return vga.zig_get_cursor_col();
}

pub fn clear_screen() void {
    if (in_ring3()) {
        _ = syscall_proxy(5, 0, 0, 0, 0);
        return;
    }
    vga.clear_screen();
}

/// Print a string slice to the console
pub fn printZ(str: []const u8) void {
    for (str) |c| {
        if (c == 0) break;
        print_char(c);
    }
}

/// Print a raw byte buffer of exact length (no null terminator search).
/// Safe for binary data; caller-provided length is authoritative.
pub fn printBuf(buf: []const u8) void {
    for (buf) |c| {
        print_char(c);
    }
}

/// Print an error message in red
pub fn printError(str: []const u8) void {
    vga.set_color(12, 0); // Red
    printZ(str);
    vga.reset_color();
}

/// Print a signed 32-bit integer to the console
pub fn printNum(n: i32) void {
    if (n < 0) {
        print_char('-');
        printNum(-n);
        return;
    }
    if (n >= 10) {
        printNum(@divTrunc(n, 10));
    }
    print_char(@intCast(@as(u8, @intCast(@mod(n, 10))) + '0'));
}

/// Print a 32-bit hex value to the console
pub fn printHex(val: u32) void {
    printZ("0x");
    var i: i8 = 7;
    while (i >= 0) : (i -= 1) {
        const nibble = @as(u8, @intCast((val >> @as(u5, @intCast(i * 4))) & 0xF));
        const char = if (nibble < 10) '0' + nibble else 'A' + (nibble - 10);
        print_char(char);
    }
}

// File System Interface
// Re-export core fs functions for easy access by shell commands
pub const fs_init = fs.fs_init;
pub const fs_create = fs.fs_create;
pub const fs_delete = fs.fs_delete;
pub const fs_find = fs.fs_find;
pub const fs_list = fs.fs_list;
pub const fs_getname = fs.fs_getname;
pub const fs_size = fs.fs_size;
pub const fs_read = fs.fs_read;
pub const fs_write = fs.fs_write;

// System Control (I/O Ports)

/// Core I/O — width (8/16/32-bit), is_out (true = write, false = read).
/// Ring 3 (user mode): uses kernel syscalls (out:7/9/17, in:6/8/16).
/// Ring 0 (kernel): native `in`/`out` instructions.
/// Returns the read value (truncated to width), or null when is_out.
fn io_port(comptime width: u6, comptime is_out: bool, port: u16, value: ?u32) ?u32 {
    const sys_in: u32, const sys_out: u32, const ret_ty: type = switch (width) {
        8  => .{ 6, 7, u8 },
        16 => .{ 8, 9, u16 },
        32 => .{ 16, 17, u32 },
        else => unreachable,
    };

    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]" : [cs] "=r" (cs));
    if ((cs & 3) == 3) {
        if (is_out) {
            asm volatile ("int $0x80"
                :
                : [sys] "{eax}" (@as(u32, sys_out)),
                  [p]   "{ebx}" (@as(u32, port)),
                  [v]   "{ecx}" (@as(u32, value orelse 0)),
            );
            return null;
        }
        return asm volatile ("int $0x80"
            : [ret] "={eax}" (-> ret_ty),
            : [sys] "{eax}" (@as(u32, sys_in)),
              [p]   "{ebx}" (@as(u32, port)),
        );
    }

    // Ring 0: native in/out via comptime-selected asm blocks.
    if (is_out) {
        const val: u32 = value orelse 0;
        const v8: u8 = @intCast(val);
        const v16: u16 = @intCast(val);
        switch (width) {
            8  => asm volatile ("outb %[v], %[p]" :: [v] "{al}" (v8), [p] "{dx}" (port)),
            16 => asm volatile ("outw %[v], %[p]" :: [v] "{ax}" (v16), [p] "{dx}" (port)),
            32 => asm volatile ("outl %[v], %[p]" :: [v] "{eax}" (val), [p] "{dx}" (port)),
            else => unreachable,
        }
        return null;
    }

    return switch (width) {
        8  => asm volatile ("inb %[p], %[r]" : [r] "={al}" (-> u8),  : [p] "{dx}" (port)),
        16 => asm volatile ("inw %[p], %[r]" : [r] "={ax}" (-> u16),  : [p] "{dx}" (port)),
        32 => asm volatile ("inl %[p], %[r]" : [r] "={eax}" (-> u32), : [p] "{dx}" (port)),
        else => unreachable,
    };
}

/// Send a byte to an I/O port
pub fn outb(port: u16, value: u8) void {
    _ = io_port(8, true, port, value);
}

/// Send a word (16-bit) to an I/O port
pub fn outw(port: u16, value: u16) void {
    _ = io_port(16, true, port, value);
}

/// Send a double word (32-bit) to an I/O port
pub fn outl(port: u16, value: u32) void {
    _ = io_port(32, true, port, value);
}

/// Read a byte from an I/O port
pub fn inb(port: u16) u8 {
    return @intCast(io_port(8, false, port, null) orelse 0);
}

/// Read a word (16-bit) from an I/O port
pub fn inw(port: u16) u16 {
    return @intCast(io_port(16, false, port, null) orelse 0);
}

/// Read a double word (32-bit) from an I/O port
pub fn inl(port: u16) u32 {
    return @intCast(io_port(32, false, port, null) orelse 0);
}

/// Reset the computer via the keyboard controller pulse
pub fn reboot() noreturn {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 14)),
        );
        while (true) {}
    }

    logger.info("Rebooting...");
    // Pulse CPU reset line (FE code to command port 64h)
    outb(0x64, 0xFE);
    while (true) {}
}

/// Shutdown the system using ACPI
pub fn shutdown() noreturn {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 13)),
        );
        while (true) {}
    }

    logger.info("Shutting down...");
    acpi.shutdown();
}

/// Precise sleep in milliseconds
pub fn sleep(ms: usize) void {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 10)),
              [val] "{ebx}" (@as(u32, @intCast(ms))),
        );
        return;
    }
    timer.sleep(ms);
}

pub fn idt_check() bool {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        var result: u32 = 0;
        asm volatile ("int $0x80"
            : [ret] "={eax}" (result),
            : [sys] "{eax}" (@as(u32, 33)),
        );
        return result == 1;
    }
    const idt_watchdog = @import("../arch/mod.zig").idt_watchdog;
    return idt_watchdog.check_idt();
}

pub fn idt_move() void {
    if (!config.ENABLE_DEBUG_COMMANDS) return;

    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        _ = asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 34)),
        );
        return;
    }
    const idt_watchdog = @import("../arch/mod.zig").idt_watchdog;
    idt_watchdog.trigger_panic();
}

var rnd_state: u32 = 0xACE1;
pub fn seed_random_with_tsc() void {
    var low: u32 = undefined;
    var high: u32 = undefined;
    asm volatile ("rdtsc"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
    );
    rnd_state = low ^ high;
    if (rnd_state == 0) rnd_state = 0xACE1;
}

pub fn get_random(min_v: i32, max_v: i32) i32 {
    if (max_v <= min_v) return min_v;
    // Xorshift PRNG
    rnd_state ^= rnd_state << 13;
    rnd_state ^= rnd_state >> 17;
    rnd_state ^= rnd_state << 5;
    const range = @as(u32, @intCast(max_v - min_v + 1));
    return @as(i32, @intCast(@mod(rnd_state, range))) + min_v;
}

pub fn endsWithIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    const start = a.len - b.len;
    for (0..b.len) |i| {
        if (asciiLower(a[start + i]) != asciiLower(b[i])) return false;
    }
    return true;
}

/// Simple indexOf for memory slices
pub fn std_mem_indexOf(comptime T: type, slice: []const T, sub: []const T) ?usize {
    if (sub.len == 0) return 0;
    if (slice.len < sub.len) return null;
    var i: usize = 0;
    while (i <= slice.len - sub.len) : (i += 1) {
        if (std_mem_eql(slice[i .. i + sub.len], sub)) return i;
    }
    return null;
}

/// Remove leading and trailing spaces
pub fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and s[start] == ' ') : (start += 1) {}
    var end: usize = s.len;
    while (end > start and s[end - 1] == ' ') : (end -= 1) {}
    return s[start..end];
}

/// Parse command line arguments with support for quoted strings
pub fn parseArgs(input: []const u8, argv: anytype) usize {
    const T = @TypeOf(argv);
    const P = @typeInfo(T).pointer;
    const A = @typeInfo(P.child).array;
    const max_args = A.len;

    var count: usize = 0;
    var i: usize = 0;
    while (i < input.len and count < max_args) {
        // Skip leading spaces
        while (i < input.len and (input[i] == ' ' or input[i] == '\t')) : (i += 1) {}
        if (i >= input.len) break;

        if (input[i] == '"') {
            i += 1; // Skip opening quote
            const start = i;
            while (i < input.len and input[i] != '"') : (i += 1) {}
            argv[count] = input[start..i];
            count += 1;
            if (i < input.len) i += 1; // Skip closing quote
        } else {
            const start = i;
            while (i < input.len and input[i] != ' ' and input[i] != '\t') : (i += 1) {}
            argv[count] = input[start..i];
            count += 1;
        }
    }
    return count;
}

/// Format string to buffer. Supports {d} and {s}.
pub fn fmt_to_buf(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    var buf_idx: usize = 0;
    comptime var fmt_idx: usize = 0;
    comptime var arg_idx: usize = 0;

    inline while (fmt_idx < fmt.len) {
        if (buf_idx >= buf.len) break;

        if (fmt_idx + 2 < fmt.len and fmt[fmt_idx] == '{') {
            const spec = fmt[fmt_idx + 1];
            if (fmt[fmt_idx + 2] == '}') {
                if (spec == 'd') {
                    buf_idx += fmtIntToBuf(buf[buf_idx..], args[arg_idx]);
                    arg_idx += 1;
                    fmt_idx += 3;
                    continue;
                } else if (spec == 's') {
                    const str = args[arg_idx];
                    for (str) |c| {
                        if (buf_idx >= buf.len) break;
                        buf[buf_idx] = c;
                        buf_idx += 1;
                    }
                    arg_idx += 1;
                    fmt_idx += 3;
                    continue;
                }
            }
        }
        buf[buf_idx] = fmt[fmt_idx];
        buf_idx += 1;
        fmt_idx += 1;
    }
    return buf[0..buf_idx];
}

fn fmtIntToBuf(buf: []u8, n_in: anytype) usize {
    var n: i32 = @intCast(n_in);
    if (n == 0) {
        if (buf.len > 0) {
            buf[0] = '0';
            return 1;
        }
        return 0;
    }

    var len: usize = 0;
    if (n < 0) {
        if (buf.len > 0) {
            buf[0] = '-';
            len = 1;
        }
        n = -n;
    }

    var temp: [12]u8 = undefined;
    var i: usize = 0;
    var un: u32 = @intCast(n);
    while (un > 0) {
        temp[i] = @intCast((un % 10) + '0');
        un /= 10;
        i += 1;
    }

    var j: usize = 0;
    while (j < i) : (j += 1) {
        if (len + j < buf.len) {
            buf[len + j] = temp[i - 1 - j];
        }
    }
    return len + i;
}

pub fn parse_int(s: []const u8) ?i32 {
    if (s.len == 0) return null;
    var res: i32 = 0;
    var i: usize = 0;
    var sign: i32 = 1;
    if (s[0] == '-') {
        sign = -1;
        i = 1;
    }
    if (i >= s.len) return null;

    // Base detection
    if (i + 2 <= s.len and s[i] == '0') {
        const next = s[i + 1];
        if (next == 'x' or next == 'X') {
            i += 2;
            while (i < s.len) : (i += 1) {
                const c = s[i];
                var digit: i32 = 0;
                if (c >= '0' and c <= '9') {
                    digit = c - '0';
                } else if (c >= 'a' and c <= 'f') {
                    digit = c - 'a' + 10;
                } else if (c >= 'A' and c <= 'F') {
                    digit = c - 'A' + 10;
                } else break;
                res = (res * 16) + digit;
            }
            return res * sign;
        } else if (next == 'b' or next == 'B') {
            i += 2;
            while (i < s.len) : (i += 1) {
                const c = s[i];
                if (c == '0' or c == '1') {
                    res = (res * 2) + @as(i32, c - '0');
                } else break;
            }
            return res * sign;
        }
    }

    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return null;
        res = res * 10 + @as(i32, @intCast(s[i] - '0'));
    }
    return res * sign;
}

pub fn intToHex(val: u32, buf: []u8) []const u8 {
    const chars = "0123456789ABCDEF";
    var idx: usize = 0;
    buf[idx] = '0';
    idx += 1;
    buf[idx] = 'x';
    idx += 1;

    // Simple 8-digit hex for u32
    var i: i32 = 7;
    while (i >= 0) : (i -= 1) {
        const nibble = (val >> @as(u5, @intCast(i * 4))) & 0xF;
        buf[idx] = chars[nibble];
        idx += 1;
    }
    return buf[0..idx];
}

pub fn intToString(val: i32, buf: []u8) []const u8 {
    if (val == 0) {
        buf[0] = '0';
        return buf[0..1];
    }

    var n = val;
    var i: usize = 0;
    var is_neg = false;

    if (n < 0) {
        is_neg = true;
        n = -n;
    }

    var temp: [16]u8 = undefined;
    var t: usize = 0;

    while (n > 0) {
        temp[t] = @intCast(@mod(n, 10));
        temp[t] += '0';
        n = @divTrunc(n, 10);
        t += 1;
    }

    if (is_neg) {
        buf[i] = '-';
        i += 1;
    }

    while (t > 0) {
        t -= 1;
        buf[i] = temp[t];
        i += 1;
    }
    return buf[0..i];
}
