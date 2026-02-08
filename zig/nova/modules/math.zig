const common = @import("../common.zig");
const global_common = @import("../../commands/common.zig");
const hash_table = @import("../hash_table.zig");

pub fn handleMath(vm: anytype, name: []const u8) ?hash_table.VariableValue {
    if (common.streq(name, "math.set_angles")) {
        const mode = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in math.set_angles");
        }

        if (mode.vtype == .string) {
            if (common.streq_ignore_case(mode.str_val, "rad")) {
                vm.angle_mode = common.AngleMode.RAD;
                return .{ .vtype = .string, .str_val = "Angle mode: RAD" };
            } else if (common.streq_ignore_case(mode.str_val, "deg")) {
                vm.angle_mode = common.AngleMode.DEG;
                return .{ .vtype = .string, .str_val = "Angle mode: DEG" };
            }
        }
        vm.reportError("math.set_angles expects \"rad\" or \"deg\"");
        return .{ .vtype = .string, .str_val = "Error" };
    } else if (common.streq(name, "math.rad")) {
        const val = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in math.rad");
        }
        const deg_v: f32 = if (val.vtype == .float) val.float_val else @floatFromInt(val.int_val);
        return .{ .vtype = .float, .float_val = deg_v * 3.14159 / 180.0 };
    } else if (common.streq(name, "math.deg")) {
        const val = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in math.deg");
        }
        const rad_v: f32 = if (val.vtype == .float) val.float_val else @floatFromInt(val.int_val);
        return .{ .vtype = .float, .float_val = rad_v * 180.0 / 3.14159 };
    } else if (common.streq(name, "math.random")) {
        const min_v = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .COMMA) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ',' in math.random");
            return .{ .vtype = .int, .int_val = 0 };
        }
        const max_v = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in math.random");
        }
        return .{ .vtype = .int, .int_val = global_common.get_random(min_v.int_val, max_v.int_val) };
    } else if (common.streq(name, "math.abs")) {
        const val = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in math.abs");
        }
        if (val.vtype == .int) {
            return .{ .vtype = .int, .int_val = if (val.int_val < 0) -val.int_val else val.int_val };
        } else if (val.vtype == .float) {
            return .{ .vtype = .float, .float_val = if (val.float_val < 0) -val.float_val else val.float_val };
        }
        return val;
    } else if (common.streq(name, "math.min")) {
        const a = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .COMMA) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ',' in math.min");
            return .{ .vtype = .int, .int_val = 0 };
        }
        const b = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in math.min");
        }
        if (a.vtype == .int and b.vtype == .int) {
            return .{ .vtype = .int, .int_val = if (a.int_val < b.int_val) a.int_val else b.int_val };
        } else if ((a.vtype == .float or a.vtype == .int) and (b.vtype == .float or b.vtype == .int)) {
            const af: f32 = if (a.vtype == .float) a.float_val else @floatFromInt(a.int_val);
            const bf: f32 = if (b.vtype == .float) b.float_val else @floatFromInt(b.int_val);
            return .{ .vtype = .float, .float_val = if (af < bf) af else bf };
        }
        return a;
    } else if (common.streq(name, "math.max")) {
        const a = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .COMMA) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ',' in math.max");
            return .{ .vtype = .int, .int_val = 0 };
        }
        const b = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in math.max");
        }
        if (a.vtype == .int and b.vtype == .int) {
            return .{ .vtype = .int, .int_val = if (a.int_val > b.int_val) a.int_val else b.int_val };
        } else if ((a.vtype == .float or a.vtype == .int) and (b.vtype == .float or b.vtype == .int)) {
            const af: f32 = if (a.vtype == .float) a.float_val else @floatFromInt(a.int_val);
            const bf: f32 = if (b.vtype == .float) b.float_val else @floatFromInt(b.int_val);
            return .{ .vtype = .float, .float_val = if (af > bf) af else bf };
        }
        return a;
    } else if (common.streq(name, "math.sin")) {
        const val_v = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in math.sin");
        }
        var d: f32 = if (val_v.vtype == .float) val_v.float_val else @floatFromInt(val_v.int_val);
        if (vm.angle_mode == common.AngleMode.RAD) {
            d = d * 180.0 / 3.14159;
        }
        while (d < 0) d += 360.0;
        while (d >= 360.0) d -= 360.0;

        var res: f32 = 0;
        if (d < 180.0) {
            const x = d;
            res = (4.0 * x * (180.0 - x)) / (40500.0 - x * (180.0 - x));
        } else {
            const x = d - 180.0;
            res = -((4.0 * x * (180.0 - x)) / (40500.0 - x * (180.0 - x)));
        }
        return .{ .vtype = .float, .float_val = res };
    } else if (common.streq(name, "math.cos")) {
        const val_v = vm.evaluateExpression();
        if (vm.ip < vm.tokens.len and vm.tokens.tokens[vm.ip].ttype == .R_PAREN) {
            vm.ip += 1;
        } else {
            vm.reportError("Expected ')' in math.cos");
        }
        var d: f32 = if (val_v.vtype == .float) val_v.float_val else @floatFromInt(val_v.int_val);
        if (vm.angle_mode == common.AngleMode.RAD) {
            d = d * 180.0 / 3.14159;
        }
        while (d < 0) d += 360.0;
        var dc = d + 90.0;
        while (dc >= 360.0) dc -= 360.0;

        var res: f32 = 0;
        if (dc < 180.0) {
            const x = dc;
            res = (4.0 * x * (180.0 - x)) / (40500.0 - x * (180.0 - x));
        } else {
            const x = dc - 180.0;
            res = -((4.0 * x * (180.0 - x)) / (40500.0 - x * (180.0 - x)));
        }
        return .{ .vtype = .float, .float_val = res };
    }
    return null;
}
