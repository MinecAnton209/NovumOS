const common = @import("../commands/common.zig");
const memory = @import("memory.zig");

var has_rdrand_feature: bool = false;
var has_rdseed_feature: bool = false;
var entropy_pool: u32 = 0;
var pending_word: u32 = 0;
var pending_bytes: u8 = 0;

// pending_word/pending_bytes drain from ring-3 qrand, syscalls 55/56 and
// every AP core: an unguarded pending_bytes -= 1 races (0-1 wraps to 255
// and serves stale bytes). cli only in ring 0; ring 3 spins while the
// holder finishes this bounded section. Taken standalone or inside sim
// (sim -> rng nesting), never before another lock.
var rng_lock: u32 = 0;

fn rngEnter() u32 {
    var eflags: u32 = undefined;
    asm volatile ("pushfl; popl %[f]"
        : [f] "=r" (eflags),
    );
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 0) asm volatile ("cli");
    while (@atomicRmw(u32, &rng_lock, .Xchg, 1, .acquire) == 1) {
        asm volatile ("pause");
    }
    return eflags;
}

fn rngLeave(eflags: u32) void {
    @atomicStore(u32, &rng_lock, 0, .release);
    asm volatile ("pushl %[f]; popfl"
        :
        : [f] "r" (eflags),
        : .{ .memory = true });
}

pub fn init() void {
    detect_rdrand();
    seed_entropy();
    // Warm reboot preserves RAM: drop any register from a previous session.
    sim_amps = null;
    sim_n = 0;
    sim_dim = 0;
    sim_cap = 0;
}

fn detect_rdrand() void {
    var eax: u32 = 1;
    var ecx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax_out] "={eax}" (eax),
          [ecx_out] "={ecx}" (ecx),
        : [eax_in] "{eax}" (eax),
        : .{ .ebx = true, .edx = true });
    has_rdrand_feature = (ecx & (1 << 30)) != 0;
    if (!has_rdrand_feature) return;

    var leaf: u32 = 7;
    const subleaf: u32 = 0;
    var ecx7: u32 = undefined;
    asm volatile ("cpuid"
        : [eax_out] "={eax}" (leaf),
          [ecx_out] "={ecx}" (ecx7),
        : [eax_in] "{eax}" (leaf),
          [ecx_in] "{ecx}" (subleaf),
        : .{ .ebx = true, .edx = true });
    has_rdseed_feature = (ecx7 & (1 << 18)) != 0;
}

fn try_rdseed() ?u32 {
    if (!has_rdseed_feature) return null;
    var attempt: u32 = 0;
    while (attempt < 10) : (attempt += 1) {
        var val: u32 = undefined;
        var carry: u8 = undefined;
        asm volatile ("rdseed %[val]\n\tsetc %[carry]"
            : [val] "=r" (val),
              [carry] "=qm" (carry),
            :
            : .{ .cc = true });
        if (carry != 0) return val;
    }
    return null;
}

fn seed_entropy() void {
    // RDSEED exposes the raw hardware entropy source — ideal pool seed,
    // while RDRAND's DRBG output serves routine byte generation.
    if (try_rdseed()) |raw| {
        entropy_pool = raw;
        return;
    }
    var lo: u32 = undefined;
    var hi: u32 = undefined;
    asm volatile ("rdtsc"
        : [lo] "={eax}" (lo),
          [hi] "={edx}" (hi),
    );
    entropy_pool = lo ^ hi;
}

/// RDRAND sample — Intel's guidance is to retry a failing sample ~10
/// times before treating the source as unavailable for this read.
fn try_rdrand() ?u32 {
    if (!has_rdrand_feature) return null;
    var attempt: u32 = 0;
    while (attempt < 10) : (attempt += 1) {
        var val: u32 = undefined;
        var carry: u8 = undefined;
        asm volatile ("rdrand %[val]\n\tsetc %[carry]"
            : [val] "=r" (val),
              [carry] "=qm" (carry),
            :
            : .{ .cc = true });
        if (carry != 0) return val;
    }
    return null;
}

fn get_entropy_word() u32 {
    if (try_rdrand()) |val| return val;
    var lo: u32 = undefined;
    var hi: u32 = undefined;
    asm volatile ("rdtsc"
        : [lo] "={eax}" (lo),
          [hi] "={edx}" (hi),
    );
    entropy_pool ^= lo ^ hi ^ (entropy_pool >> 16);
    entropy_pool = (entropy_pool << 7) | (entropy_pool >> 25);
    return entropy_pool;
}

/// One rdrand sample feeds four bytes: the buffered word is drained
/// before the next 32-bit hardware read (was: one call per byte).
fn get_entropy_byte() u8 {
    const eflags = rngEnter();
    defer rngLeave(eflags);
    if (pending_bytes == 0) {
        pending_word = get_entropy_word();
        pending_bytes = 4;
    }
    const b: u8 = @intCast(pending_word & 0xFF);
    pending_word >>= 8;
    pending_bytes -= 1;
    return b;
}

pub fn randByte() u8 {
    return get_entropy_byte();
}

/// Two bytes correlated bit-by-bit through a real Bell state: for each
/// bit, |00⟩ → H(0) → CNOT(0,1) → measure both qubits. Ideal
/// simulation ⇒ the pair always matches (no fake decoherence).
pub fn entangledPair() [2]u8 {
    const eflags = simEnter();
    defer simLeave(eflags);

    var a: u8 = 0;
    var b: u8 = 0;
    for (0..8) |bit_idx| {
        switch (simInitLocked(2)) {
            .ok => {},
            else => break,
        }
        _ = applyHLocked(0);
        _ = applyCNOTLocked(0, 1);
        const m0 = measureLocked(0) orelse break;
        const m1 = measureLocked(1) orelse break;
        if (m0) a |= @as(u8, 1) << @as(u3, @intCast(bit_idx));
        if (m1) b |= @as(u8, 1) << @as(u3, @intCast(bit_idx));
    }
    return .{ a, b };
}

pub fn fillBuf(buf: []u8) void {
    for (buf) |*b| {
        b.* = randByte();
    }
}

pub fn hasRdrand() bool {
    return has_rdrand_feature;
}

pub const Complex = struct { re: f64, im: f64 };

/// Heap-backed register; the heap caps a single alloc at 16 MB, which
/// bounds n before the OS reserve ever could.
pub const MAX_QUBITS = 19;
const OS_RESERVE: usize = 32 * 1024 * 1024;

var sim_amps: ?[*]Complex = null;
var sim_n: usize = 0;
var sim_dim: usize = 0;
var sim_cap: usize = 0;
var sim_bits: [MAX_QUBITS]usize = undefined;

pub const InitResult = union(enum) {
    ok: usize,
    bad_qubits: void,
    insufficient: struct { need: usize, avail: usize },
    oom: usize,
};

// The register is global state reachable from the shell, syscall 57 and
// any SMP core — every public entry takes this lock. Ring 0 callers run
// cli'd; ring 3 cannot cli, but an interrupted ring-3 section is safe:
// schedule() never touches simulator state.
var sim_lock: u32 = 0;

fn simEnter() u32 {
    var eflags: u32 = undefined;
    asm volatile ("pushfl; popl %[f]"
        : [f] "=r" (eflags),
    );
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 0) asm volatile ("cli");
    while (@atomicRmw(u32, &sim_lock, .Xchg, 1, .acquire) == 1) {
        asm volatile ("pause");
    }
    return eflags;
}

fn simLeave(eflags: u32) void {
    @atomicStore(u32, &sim_lock, 0, .release);
    asm volatile ("pushl %[f]; popfl"
        :
        : [f] "r" (eflags),
        : .{ .memory = true });
}

pub fn simInit(n: usize) InitResult {
    const eflags = simEnter();
    defer simLeave(eflags);
    return simInitLocked(n);
}

/// Reset the register to |0…0⟩ with n qubits. The buffer comes from the
/// kernel heap; sizes that would eat into the 32 MB OS reserve are
/// refused with the actual numbers so qinit can print them.
/// Caller must hold the sim lock.
fn simInitLocked(n: usize) InitResult {
    if (n == 0 or n > MAX_QUBITS) return .{ .bad_qubits = {} };

    var dim: usize = 1;
    var i: usize = 0;
    while (i < n) : (i += 1) dim *= 2;
    const need = dim * @sizeOf(Complex);

    const free = memory.get_free_memory();
    const avail = if (free > OS_RESERVE) free - OS_RESERVE else 0;
    if (need > avail) return .{ .insufficient = .{ .need = need, .avail = avail } };

    if (sim_amps == null or sim_cap < dim) {
        const buf = memory.heap.alloc(need) orelse return .{ .oom = need };
        if (sim_amps) |old| memory.heap.free(@ptrCast(old));
        const p: [*]Complex = @ptrCast(@alignCast(buf));
        sim_amps = p;
        sim_cap = dim;
    }

    const amps = sim_amps.?;
    i = 0;
    while (i < dim) : (i += 1) amps[i] = .{ .re = 0, .im = 0 };
    amps[0] = .{ .re = 1, .im = 0 };
    sim_n = n;
    sim_dim = dim;

    var bit: usize = 1;
    i = 0;
    while (i < n) : (i += 1) {
        sim_bits[i] = bit;
        bit *= 2;
    }
    return .{ .ok = need };
}

fn initOk(n: usize) bool {
    // Called only from selfTest, which holds the sim lock.
    return switch (simInitLocked(n)) {
        .ok => true,
        else => false,
    };
}

fn qubitOk(q: usize) bool {
    return sim_n != 0 and q < sim_n;
}

pub fn applyX(target: usize) bool {
    const eflags = simEnter();
    defer simLeave(eflags);
    return applyXLocked(target);
}

fn applyXLocked(target: usize) bool {
    if (!qubitOk(target)) return false;
    const amps = sim_amps.?;
    const bit = sim_bits[target];
    const dim = sim_dim;
    var i: usize = 0;
    while (i < dim) : (i += 1) {
        if ((i & bit) == 0) {
            const j = i | bit;
            const t = amps[i];
            amps[i] = amps[j];
            amps[j] = t;
        }
    }
    return true;
}

pub fn applyH(target: usize) bool {
    const eflags = simEnter();
    defer simLeave(eflags);
    return applyHLocked(target);
}

fn applyHLocked(target: usize) bool {
    if (!qubitOk(target)) return false;
    const amps = sim_amps.?;
    const bit = sim_bits[target];
    const dim = sim_dim;
    const s = 1.0 / @sqrt(2.0);
    var i: usize = 0;
    while (i < dim) : (i += 1) {
        if ((i & bit) == 0) {
            const j = i | bit;
            const a = amps[i];
            const b = amps[j];
            amps[i] = .{ .re = (a.re + b.re) * s, .im = (a.im + b.im) * s };
            amps[j] = .{ .re = (a.re - b.re) * s, .im = (a.im - b.im) * s };
        }
    }
    return true;
}

pub fn applyCNOT(control: usize, target: usize) bool {
    const eflags = simEnter();
    defer simLeave(eflags);
    return applyCNOTLocked(control, target);
}

fn applyCNOTLocked(control: usize, target: usize) bool {
    if (!qubitOk(control) or !qubitOk(target) or control == target) return false;
    const amps = sim_amps.?;
    const cbit = sim_bits[control];
    const tbit = sim_bits[target];
    const dim = sim_dim;
    var i: usize = 0;
    while (i < dim) : (i += 1) {
        if ((i & cbit) != 0 and (i & tbit) == 0) {
            const j = i | tbit;
            const t = amps[i];
            amps[i] = amps[j];
            amps[j] = t;
        }
    }
    return true;
}

fn ampProb(c: Complex) f64 {
    return c.re * c.re + c.im * c.im;
}

fn randFloat() f64 {
    var v: u32 = 0;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        v = (v << 8) | @as(u32, randByte());
    }
    return @as(f64, @floatFromInt(v)) * (1.0 / 4294967296.0);
}

/// Born-rule measurement: P(1) is the summed |amp|² over basis states
/// with the target bit set. After drawing the outcome, incompatible
/// amplitudes are zeroed and the survivors renormalized.
pub fn measure(target: usize) ?bool {
    const eflags = simEnter();
    defer simLeave(eflags);
    return measureLocked(target);
}

/// Caller must hold the sim lock.
fn measureLocked(target: usize) ?bool {
    if (!qubitOk(target)) return null;
    const amps = sim_amps.?;
    const bit = sim_bits[target];
    const dim = sim_dim;

    var p_one: f64 = 0;
    var i: usize = 0;
    while (i < dim) : (i += 1) {
        if ((i & bit) != 0) p_one += ampProb(amps[i]);
    }
    const got_one = randFloat() < p_one;

    var norm2: f64 = 0;
    i = 0;
    while (i < dim) : (i += 1) {
        if (((i & bit) != 0) != got_one) {
            amps[i] = .{ .re = 0, .im = 0 };
        } else {
            norm2 += ampProb(amps[i]);
        }
    }
    if (norm2 > 0) {
        const inv = 1.0 / @sqrt(norm2);
        i = 0;
        while (i < dim) : (i += 1) {
            amps[i].re *= inv;
            amps[i].im *= inv;
        }
    }
    return got_one;
}

pub const TestResult = struct {
    x_ok: bool,
    trials: usize,
    zero_zero: usize,
    one_one: usize,
    mixed: usize,
};

/// Self-check: X|0⟩ must measure 1, and Bell states may only yield
/// 00 or 11 — any mixed result means CNOT or collapse is broken.
pub fn selfTest(trials: usize) TestResult {
    const eflags = simEnter();
    defer simLeave(eflags);

    var res = TestResult{
        .x_ok = false,
        .trials = trials,
        .zero_zero = 0,
        .one_one = 0,
        .mixed = 0,
    };

    if (initOk(2) and applyXLocked(1)) {
        const m0 = measureLocked(0);
        const m1 = measureLocked(1);
        if (m0 != null and m1 != null) {
            res.x_ok = !m0.? and m1.?;
        }
    }

    var t: usize = 0;
    while (t < trials) : (t += 1) {
        if (!initOk(2) or !applyHLocked(0) or !applyCNOTLocked(0, 1)) break;
        const m0 = measureLocked(0) orelse break;
        const m1 = measureLocked(1) orelse break;
        if (!m0 and !m1) {
            res.zero_zero += 1;
        } else if (m0 and m1) {
            res.one_one += 1;
        } else {
            res.mixed += 1;
        }
    }
    return res;
}
