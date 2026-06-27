const common = @import("../common.zig");
const speaker = @import("../../drivers/speaker.zig");
const hash_table = @import("../hash_table.zig");

pub fn handleSpeaker(_: anytype, name: []const u8, args: []const hash_table.VariableValue) ?hash_table.VariableValue {
    if (common.streq(name, "speaker.beep")) {
        const freq: u32 = if (args.len >= 1 and args[0].vtype == .int) @intCast(args[0].int_val) else 440;
        const dur_ms: u32 = if (args.len >= 2 and args[1].vtype == .int) @intCast(args[1].int_val) else 200;
        speaker.beep_async(freq, dur_ms);
        return .{ .vtype = .string, .str_val = "" };
    }
    return null;
}
