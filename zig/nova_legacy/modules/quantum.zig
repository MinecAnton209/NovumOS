const common = @import("../common.zig");
const quantum = @import("../../quantum.zig");
const hash_table = @import("../hash_table.zig");

pub fn handleQuantum(vm: anytype, name: []const u8) ?hash_table.VariableValue {
    if (common.streq(name, "quantum.rand")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in quantum.rand");
        }
        return .{ .vtype = .int, .int_val = @intCast(quantum.randByte()) };
    }
    if (common.streq(name, "quantum.entangle")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in quantum.entangle");
        }
        const pair = quantum.entangledPair();
        const p_val = @as(i32, @intCast(pair[0])) | (@as(i32, @intCast(pair[1])) << 8);
        return .{ .vtype = .int, .int_val = p_val };
    }
    if (common.streq(name, "quantum.info")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        }
        if (quantum.hasRdrand()) {
            return .{ .vtype = .string, .str_val = "RDRAND=yes mode=quantum" };
        }
        return .{ .vtype = .string, .str_val = "RDRAND=no mode=jitter" };
    }
    return null;
}
