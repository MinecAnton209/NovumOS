const common = @import("../commands/common.zig");

var has_rdrand_feature: bool = false;
var has_rdseed_feature: bool = false;
var entropy_pool: u32 = 0;
var pending_word: u32 = 0;
var pending_bytes: u8 = 0;

pub fn init() void {
    detect_rdrand();
    seed_entropy();
}

fn detect_rdrand() void {
    var eax: u32 = 1;
    var ecx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax_out] "={eax}" (eax),
          [ecx_out] "={ecx}" (ecx),
        : [eax_in] "{eax}" (eax),
        : .{ .ebx = true, .edx = true }
    );
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
        : .{ .ebx = true, .edx = true }
    );
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
              [carry] "=qm" (carry)
            :
            : .{ .cc = true }
        );
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
              [carry] "=qm" (carry)
            :
            : .{ .cc = true }
        );
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

/// Bell state |Φ⁺⟩ = (|00⟩ + |11⟩) / √2 — two bytes that match
/// almost every bit (~98 %) with simulated decoherence.
pub fn entangledPair() [2]u8 {
    const a = randByte();
    var b: u8 = 0;
    for (0..8) |i| {
        const bit = (a >> @as(u3, @intCast(i))) & 1;
        if (get_entropy_byte() < 250) {
            b |= bit << @as(u3, @intCast(i));
        } else {
            b |= (bit ^ 1) << @as(u3, @intCast(i));
        }
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

pub const MAX_QUBITS = 3;
const SIM_DIMS: [MAX_QUBITS + 1]usize = .{ 0, 2, 4, 8 };
const QBIT_MASK: [MAX_QUBITS]usize = .{ 1, 2, 4 };

var sim_amps: [8]Complex = undefined;
var sim_n: usize = 0;

/// Reset the register to |0…0⟩ with n qubits. Fixed 8-amplitude buffer
/// covers 3 qubits — no allocator; raise MAX_QUBITS once a heap exists.
pub fn simInit(n: usize) bool {
    if (n == 0 or n > MAX_QUBITS) return false;
    sim_n = n;
    var i: usize = 0;
    while (i < sim_amps.len) : (i += 1) {
        sim_amps[i] = .{ .re = 0, .im = 0 };
    }
    sim_amps[0] = .{ .re = 1, .im = 0 };
    return true;
}

fn qubitOk(q: usize) bool {
    return sim_n != 0 and q < sim_n;
}

pub fn applyX(target: usize) bool {
    if (!qubitOk(target)) return false;
    const bit = QBIT_MASK[target];
    const dim = SIM_DIMS[sim_n];
    var i: usize = 0;
    while (i < dim) : (i += 1) {
        if ((i & bit) == 0) {
            const j = i | bit;
            const t = sim_amps[i];
            sim_amps[i] = sim_amps[j];
            sim_amps[j] = t;
        }
    }
    return true;
}

pub fn applyH(target: usize) bool {
    if (!qubitOk(target)) return false;
    const bit = QBIT_MASK[target];
    const dim = SIM_DIMS[sim_n];
    const s = 1.0 / @sqrt(2.0);
    var i: usize = 0;
    while (i < dim) : (i += 1) {
        if ((i & bit) == 0) {
            const j = i | bit;
            const a = sim_amps[i];
            const b = sim_amps[j];
            sim_amps[i] = .{ .re = (a.re + b.re) * s, .im = (a.im + b.im) * s };
            sim_amps[j] = .{ .re = (a.re - b.re) * s, .im = (a.im - b.im) * s };
        }
    }
    return true;
}

pub fn applyCNOT(control: usize, target: usize) bool {
    if (!qubitOk(control) or !qubitOk(target) or control == target) return false;
    const cbit = QBIT_MASK[control];
    const tbit = QBIT_MASK[target];
    const dim = SIM_DIMS[sim_n];
    var i: usize = 0;
    while (i < dim) : (i += 1) {
        if ((i & cbit) != 0 and (i & tbit) == 0) {
            const j = i | tbit;
            const t = sim_amps[i];
            sim_amps[i] = sim_amps[j];
            sim_amps[j] = t;
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
    if (!qubitOk(target)) return null;
    const bit = QBIT_MASK[target];
    const dim = SIM_DIMS[sim_n];

    var p_one: f64 = 0;
    var i: usize = 0;
    while (i < dim) : (i += 1) {
        if ((i & bit) != 0) p_one += ampProb(sim_amps[i]);
    }
    const got_one = randFloat() < p_one;

    var norm2: f64 = 0;
    i = 0;
    while (i < dim) : (i += 1) {
        if (((i & bit) != 0) != got_one) {
            sim_amps[i] = .{ .re = 0, .im = 0 };
        } else {
            norm2 += ampProb(sim_amps[i]);
        }
    }
    if (norm2 > 0) {
        const inv = 1.0 / @sqrt(norm2);
        i = 0;
        while (i < dim) : (i += 1) {
            sim_amps[i].re *= inv;
            sim_amps[i].im *= inv;
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
    var res = TestResult{
        .x_ok = false,
        .trials = trials,
        .zero_zero = 0,
        .one_one = 0,
        .mixed = 0,
    };

    if (simInit(2) and applyX(1)) {
        const m0 = measure(0);
        const m1 = measure(1);
        if (m0 != null and m1 != null) {
            res.x_ok = !m0.? and m1.?;
        }
    }

    var t: usize = 0;
    while (t < trials) : (t += 1) {
        if (!simInit(2) or !applyH(0) or !applyCNOT(0, 1)) break;
        const m0 = measure(0) orelse break;
        const m1 = measure(1) orelse break;
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
