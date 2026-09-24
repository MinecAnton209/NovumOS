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
