const common = @import("../common.zig");
const speaker = @import("../../drivers/speaker.zig");
const hash_table = @import("../hash_table.zig");

pub fn handleSpeaker(vm: anytype, name: []const u8) ?hash_table.VariableValue {
    if (common.streq(name, "speaker.beep")) {
        const freq_val = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .COMMA) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ',' in speaker.beep");
            return .{ .vtype = .string, .str_val = "" };
        }
        const dur_val = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in speaker.beep");
            return .{ .vtype = .string, .str_val = "" };
        }
        const freq: u32 = if (freq_val.vtype == .int) @intCast(freq_val.int_val) else 440;
        const dur_ms: u32 = if (dur_val.vtype == .int) @intCast(dur_val.int_val) else 200;
        speaker.beep_async(freq, dur_ms);
        return .{ .vtype = .string, .str_val = "" };
    }
    return null;
}
