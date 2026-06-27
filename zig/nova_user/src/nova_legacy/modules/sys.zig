const common = @import("../common.zig");
const global_common = @import("../../commands/common.zig");
const hash_table = @import("../hash_table.zig");
const lfb = @import("../../drivers/lfb.zig");
const timer = @import("../../drivers/timer.zig");

pub fn handleSys(vm: anytype, name: []const u8, args: []const hash_table.VariableValue) ?hash_table.VariableValue {
    const default0 = hash_table.VariableValue{ .vtype = .int, .int_val = 0 };
    if (common.streq(name, "sys.get_mem")) {
        var result: u32 = 0;
        asm volatile ("int $0x80"
            : [ret] "={eax}" (result),
            : [sys] "{eax}" (@as(u32, 44)),
        );
        return .{ .vtype = .int, .int_val = @intCast(result) };
    } else if (common.streq(name, "sys.get_temp")) {
        return .{ .vtype = .int, .int_val = -1 };
    } else if (common.streq(name, "sys.delay") or common.streq(name, "sys.sleep")) {
        const val = if (args.len >= 1) args[0] else default0;
        if (val.vtype == .int) {
            global_common.sleep(@intCast(val.int_val));
        }
        return .{ .vtype = .string, .str_val = "" };
    } else if (common.streq(name, "sys.exec") or common.streq(name, "sys.shell")) {
        if (args.len >= 1 and args[0].vtype == .string) {
            _ = global_common.syscall2(53, @intFromPtr(args[0].str_val.ptr), @intCast(args[0].str_val.len));
        }
        return .{ .vtype = .string, .str_val = "" };
    } else if (common.streq(name, "sys.color")) {
        const fg_val: u8 = if (args.len >= 1 and args[0].vtype == .int) @intCast(args[0].int_val) else 15;
        const bg_val: u8 = if (args.len >= 2 and args[1].vtype == .int) @intCast(args[1].int_val) else 0;
        _ = global_common.syscall2(54, fg_val, bg_val);
        return .{ .vtype = .string, .str_val = "" };
    } else if (common.streq(name, "sys.key")) {
        return .{ .vtype = .int, .int_val = @intCast(global_common.get_char()) };
    } else if (common.streq(name, "sys.whoami")) {
        return .{ .vtype = .string, .str_val = "admin" };
    } else if (common.streq(name, "sys.uname")) {
        return .{ .vtype = .string, .str_val = "NovumOS x86_32" };
    } else if (common.streq(name, "sys.uptime")) {
        return .{ .vtype = .int, .int_val = @intCast(timer.get_ticks() / 100) };
    } else if (common.streq(name, "sys.get_res_x")) {
        return .{ .vtype = .int, .int_val = @intCast(lfb.width) };
    } else if (common.streq(name, "sys.get_res_y")) {
        return .{ .vtype = .int, .int_val = @intCast(lfb.height) };
    } else if (common.streq(name, "sys.cls")) {
        common.clear_screen();
        return .{ .vtype = .string, .str_val = "" };
    } else if (common.streq(name, "sys.exit")) {
        vm.exit_flag = true;
        return .{ .vtype = .string, .str_val = "" };
    }
    return null;
}
