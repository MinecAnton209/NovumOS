const common = @import("../common.zig");
const global_common = @import("../../commands/common.zig");
const hash_table = @import("../hash_table.zig");

pub fn handleMath(vm: anytype, name: []const u8, args: []const hash_table.VariableValue) ?hash_table.VariableValue {
    const default0 = hash_table.VariableValue{ .vtype = .int, .int_val = 0 };
    if (common.streq(name, "math.set_angles")) {
        if (args.len >= 1 and args[0].vtype == .string) {
            if (common.streq_ignore_case(args[0].str_val, "rad")) {
                vm.angle_mode = common.AngleMode.RAD;
                return .{ .vtype = .string, .str_val = "Angle mode: RAD" };
            } else if (common.streq_ignore_case(args[0].str_val, "deg")) {
                vm.angle_mode = common.AngleMode.DEG;
                return .{ .vtype = .string, .str_val = "Angle mode: DEG" };
            }
        }
        return .{ .vtype = .string, .str_val = "Error" };
    } else if (common.streq(name, "math.pi")) {
        return .{ .vtype = .float, .float_val = 3.1415926535 };
    } else if (common.streq(name, "math.rad")) {
        const val = if (args.len >= 1) args[0] else default0;
        const deg_v: f32 = if (val.vtype == .float) val.float_val else @floatFromInt(val.int_val);
        return .{ .vtype = .float, .float_val = deg_v * 3.14159 / 180.0 };
    } else if (common.streq(name, "math.deg")) {
        const val = if (args.len >= 1) args[0] else default0;
        const rad_v: f32 = if (val.vtype == .float) val.float_val else @floatFromInt(val.int_val);
        return .{ .vtype = .float, .float_val = rad_v * 180.0 / 3.14159 };
    } else if (common.streq(name, "math.random")) {
        const default1 = hash_table.VariableValue{ .vtype = .int, .int_val = 1 };
        const min_v = if (args.len >= 1) args[0] else default0;
        const max_v = if (args.len >= 2) args[1] else default1;
        return .{ .vtype = .int, .int_val = global_common.get_random(min_v.int_val, max_v.int_val) };
    } else if (common.streq(name, "math.abs")) {
        if (args.len >= 1) {
            if (args[0].vtype == .int) {
                return .{ .vtype = .int, .int_val = if (args[0].int_val < 0) -args[0].int_val else args[0].int_val };
            } else if (args[0].vtype == .float) {
                return .{ .vtype = .float, .float_val = if (args[0].float_val < 0) -args[0].float_val else args[0].float_val };
            }
            return args[0];
        }
        return default0;
    } else if (common.streq(name, "math.min")) {
        const a = if (args.len >= 1) args[0] else default0;
        const b = if (args.len >= 2) args[1] else default0;
        if (a.vtype == .int and b.vtype == .int) {
            return .{ .vtype = .int, .int_val = if (a.int_val < b.int_val) a.int_val else b.int_val };
        } else if ((a.vtype == .float or a.vtype == .int) and (b.vtype == .float or b.vtype == .int)) {
            const af: f32 = if (a.vtype == .float) a.float_val else @floatFromInt(a.int_val);
            const bf: f32 = if (b.vtype == .float) b.float_val else @floatFromInt(b.int_val);
            return .{ .vtype = .float, .float_val = if (af < bf) af else bf };
        }
        return a;
    } else if (common.streq(name, "math.max")) {
        const a = if (args.len >= 1) args[0] else default0;
        const b = if (args.len >= 2) args[1] else default0;
        if (a.vtype == .int and b.vtype == .int) {
            return .{ .vtype = .int, .int_val = if (a.int_val > b.int_val) a.int_val else b.int_val };
        } else if ((a.vtype == .float or a.vtype == .int) and (b.vtype == .float or b.vtype == .int)) {
            const af: f32 = if (a.vtype == .float) a.float_val else @floatFromInt(a.int_val);
            const bf: f32 = if (b.vtype == .float) b.float_val else @floatFromInt(b.int_val);
            return .{ .vtype = .float, .float_val = if (af > bf) af else bf };
        }
        return a;
    } else if (common.streq(name, "math.sin")) {
        const val = if (args.len >= 1) args[0] else default0;
        var d: f32 = if (val.vtype == .float) val.float_val else @floatFromInt(val.int_val);
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
        const val = if (args.len >= 1) args[0] else default0;
        var d: f32 = if (val.vtype == .float) val.float_val else @floatFromInt(val.int_val);
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
    } else if (common.streq(name, "math.sqrt")) {
        const val = if (args.len >= 1) args[0] else default0;
        const x: f32 = if (val.vtype == .float) val.float_val else @floatFromInt(val.int_val);
        if (x < 0) return .{ .vtype = .float, .float_val = 0 };
        var root: f32 = x / 2.0;
        if (root < 1) root = 1;
        var iter: usize = 0;
        while (iter < 15) : (iter += 1) {
            root = (root + x / root) / 2.0;
        }
        return .{ .vtype = .float, .float_val = root };
    } else if (common.streq(name, "math.pow")) {
        const base_v = if (args.len >= 1) args[0] else default0;
        const exp_v = if (args.len >= 2) args[1] else default0;
        const base: f32 = if (base_v.vtype == .float) base_v.float_val else @floatFromInt(base_v.int_val);
        if (exp_v.vtype == .int) {
            var res: f32 = 1.0;
            var exp = exp_v.int_val;
            const neg = exp < 0;
            if (neg) exp = -exp;
            var j: i32 = 0;
            while (j < exp) : (j += 1) res *= base;
            if (neg) res = 1.0 / res;
            return .{ .vtype = .float, .float_val = res };
        }
        return .{ .vtype = .float, .float_val = base };
    } else if (common.streq(name, "math.floor")) {
        if (args.len >= 1) {
            if (args[0].vtype == .int) return args[0];
            const f = args[0].float_val;
            if (f < 0) return .{ .vtype = .int, .int_val = @as(i32, @intFromFloat(f)) - 1 };
            return .{ .vtype = .int, .int_val = @intFromFloat(f) };
        }
        return default0;
    } else if (common.streq(name, "math.ceil")) {
        if (args.len >= 1) {
            if (args[0].vtype == .int) return args[0];
            const f = args[0].float_val;
            const i = @as(i32, @intFromFloat(f));
            if (f > @as(f32, @floatFromInt(i))) return .{ .vtype = .int, .int_val = i + 1 };
            return .{ .vtype = .int, .int_val = i };
        }
        return default0;
    } else if (common.streq(name, "math.round")) {
        if (args.len >= 1) {
            if (args[0].vtype == .int) return args[0];
            const f = args[0].float_val;
            return .{ .vtype = .int, .int_val = @intFromFloat(f + 0.5) };
        }
        return default0;
    }
    return null;
}
