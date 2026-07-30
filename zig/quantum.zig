const common = @import("commands/common.zig");

var has_rdrand_feature: bool = false;
var entropy_pool: u32 = 0;

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
}

fn seed_entropy() void {
    var lo: u32 = undefined;
    var hi: u32 = undefined;
    asm volatile ("rdtsc"
        : [lo] "={eax}" (lo),
          [hi] "={edx}" (hi),
    );
    entropy_pool = lo ^ hi;
}

/// RDRAND instruction — uses CPU thermal noise (quantum in nature).
/// Falls back to RDTSC jitter + pool mixing if unavailable.
fn try_rdrand() ?u32 {
    if (!has_rdrand_feature) return null;
    var val: u32 = undefined;
    var carry: u8 = undefined;
    asm volatile ("rdrand %[val]\n\tsetc %[carry]"
        : [val] "=r" (val),
          [carry] "=qm" (carry)
        :
        : .{ .cc = true }
    );
    return if (carry != 0) val else null;
}

fn get_entropy_byte() u8 {
    if (try_rdrand()) |val| {
        entropy_pool ^= val;
        return @intCast(entropy_pool & 0xFF);
    }
    var lo: u32 = undefined;
    var hi: u32 = undefined;
    asm volatile ("rdtsc"
        : [lo] "={eax}" (lo),
          [hi] "={edx}" (hi),
    );
    entropy_pool ^= lo ^ hi ^ (entropy_pool >> 16);
    entropy_pool = (entropy_pool << 7) | (entropy_pool >> 25);
    return @intCast(entropy_pool & 0xFF);
}

/// Collapse one qubit to |0⟩ or |1⟩ with equal probability.
fn measure_qubit() bool {
    return (get_entropy_byte() & 1) != 0;
}

/// Measure 8 independent qubits to produce a uniformly random byte.
pub fn randByte() u8 {
    var result: u8 = 0;
    for (0..8) |_| {
        result >>= 1;
        if (measure_qubit()) {
            result |= 0x80;
        }
    }
    return result;
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
