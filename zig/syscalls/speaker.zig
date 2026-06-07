// zig/syscalls/speaker.zig
// Speaker syscalls (beep, async beep, patterns).

const common = @import("../commands/common.zig");
const user = @import("../user.zig");
const speaker = @import("../drivers/speaker.zig");

/// Syscall 42: SpeakerOp(EBX=op, ECX=freq, EDX=dur_ms, ESI=gap_ms)
///   op=0: beep_async(freq, dur)
///   op=1: check — no-op with state reported via return value
///   op=2: beep_pattern_async(freq, dur, gap)
/// Returns EAX: 1 if beep pending, 0 if not.
pub fn speakerOp(regs: *user.Registers) void {
    if (regs.ebx == 0) {
        speaker.beep_async(regs.ecx, regs.edx);
    } else if (regs.ebx == 1) {
        speaker.beep_async_check();
    } else if (regs.ebx == 2) {
        speaker.beep_pattern_async(regs.ecx, regs.edx, regs.esi);
    }
    regs.eax = if (speaker.beep_async_is_pending()) 1 else 0;
}
