const common = @import("../common.zig");
const global_common = @import("../../commands/common.zig");
const hash_table = @import("../hash_table.zig");
const memory = @import("../../memory.zig");
const keyboard = @import("../../keyboard_isr.zig");
const vga = @import("../../drivers/vga.zig");
const shell = @import("../../shell.zig");

pub fn handleSys(vm: anytype, name: []const u8) ?hash_table.VariableValue {
    if (common.streq(name, "sys.get_mem")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.get_mem");
        }
        return .{ .vtype = .int, .int_val = @intCast(memory.get_free_memory()) };
    } else if (common.streq(name, "sys.get_temp")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.get_temp");
        }
        var eax_val: u32 = 0;
        var edx_val: u32 = 0;
        const msr: u32 = 0x19C;
        asm volatile ("rdmsr"
            : [eax] "={eax}" (eax_val),
              [edx] "={edx}" (edx_val),
            : [ecx] "{ecx}" (msr),
        );
        const readout = (eax_val >> 16) & 0x7F;
        return .{ .vtype = .int, .int_val = @intCast(100 - readout) };
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
    } else if (common.streq(name, "sys.exec")) {
        const val = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.exec");
        }
        if (val.vtype == .string) {
            shell.shell_execute_literal(val.str_val);
        }
        return .{ .vtype = .string, .str_val = "" };
    } else if (common.streq(name, "sys.shell")) {
        const val = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.shell");
        }
        if (val.vtype == .string) {
            shell.shell_execute_literal(val.str_val);
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
        vga.set_color(@intCast(fg.int_val), @intCast(bg.int_val));
        return .{ .vtype = .string, .str_val = "Colors updated" };
    } else if (common.streq(name, "sys.key")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.key");
        }
        return .{ .vtype = .int, .int_val = @intCast(keyboard.keyboard_getchar()) };
    } else if (common.streq(name, "sys.reboot")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.reboot");
        }
        shell.shell_execute_literal("reboot");
        return .{ .vtype = .string, .str_val = "" };
    } else if (common.streq(name, "sys.shutdown")) {
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in sys.shutdown");
        }
        shell.shell_execute_literal("shutdown");
        return .{ .vtype = .string, .str_val = "" };
    }
    return null;
}
