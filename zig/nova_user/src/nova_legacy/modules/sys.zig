const common = @import("../common.zig");
const global_common = @import("../../commands/common.zig");
const hash_table = @import("../hash_table.zig");
const lfb = @import("../../drivers/lfb.zig");
const timer = @import("../../drivers/timer.zig");

pub fn handleSys(vm: anytype, name: []const u8) ?hash_table.VariableValue {
    if (common.streq(name, "sys.get_mem")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.get_mem");
        }
        // Syscall 44 returns free physical memory in bytes.
        var result: u32 = 0;
        asm volatile ("int $0x80"
            : [ret] "={eax}" (result),
            : [sys] "{eax}" (@as(u32, 44)),
        );
        return .{ .vtype = .int, .int_val = @intCast(result) };
    } else if (common.streq(name, "sys.get_temp")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.get_temp");
        }
        // CPU temperature requires ACPI thermal zone support which isn't
        // implemented. Return -1 as a sentinel so callers can detect absence.
        return .{ .vtype = .int, .int_val = -1 };
    } else if (common.streq(name, "sys.delay") or common.streq(name, "sys.sleep")) {
        const val = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.delay");
        }
        if (val.vtype == .int) {
            global_common.sleep(@intCast(val.int_val));
        }
        return .{ .vtype = .string, .str_val = "" };
        } else if (common.streq(name, "sys.exec") or common.streq(name, "sys.shell")) {
            const cmd = vm.evaluateExpression();
            if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
                vm.ip += 1;
            } else {
                vm.reportError("Expected ')' in sys.exec");
            }
            if (cmd.vtype == .string) {
                _ = global_common.syscall2(53, @intFromPtr(cmd.str_val.ptr), @intCast(cmd.str_val.len));
            }
            return .{ .vtype = .string, .str_val = "" };
    } else if (common.streq(name, "sys.color")) {
        const fg = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .COMMA) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ',' in sys.color");
            return .{ .vtype = .string, .str_val = "Error" };
        }
        const bg = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.color");
        }
        const fg_val: u8 = if (fg.vtype == .int) @intCast(fg.int_val) else 15;
        const bg_val: u8 = if (bg.vtype == .int) @intCast(bg.int_val) else 0;
        _ = global_common.syscall2(54, fg_val, bg_val);
        return .{ .vtype = .string, .str_val = "" };
    } else if (common.streq(name, "sys.key")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.key");
        }
        return .{ .vtype = .int, .int_val = @intCast(global_common.get_char()) };
        } else if (common.streq(name, "sys.whoami")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) vm.ip += 1;
        return .{ .vtype = .string, .str_val = "admin" };
    } else if (common.streq(name, "sys.uname")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) vm.ip += 1;
        return .{ .vtype = .string, .str_val = "NovumOS x86_32" };
    } else if (common.streq(name, "sys.uptime")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) vm.ip += 1;
        return .{ .vtype = .int, .int_val = @intCast(timer.get_ticks() / 100) };
    } else if (common.streq(name, "sys.get_res_x")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) vm.ip += 1;
        return .{ .vtype = .int, .int_val = @intCast(lfb.width) };
    } else if (common.streq(name, "sys.get_res_y")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) vm.ip += 1;
        return .{ .vtype = .int, .int_val = @intCast(lfb.height) };
    } else if (common.streq(name, "sys.cls")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) vm.ip += 1;
        common.clear_screen();
        return .{ .vtype = .string, .str_val = "" };
    } else if (common.streq(name, "sys.exit")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        }
        vm.exit_flag = true;
        return .{ .vtype = .string, .str_val = "" };
    }
    return null;
}
