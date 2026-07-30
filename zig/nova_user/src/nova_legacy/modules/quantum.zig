const common = @import("../common.zig");
const hash_table = @import("../hash_table.zig");

pub fn handleQuantum(_: anytype, name: []const u8, _: []const hash_table.VariableValue) ?hash_table.VariableValue {
    if (common.streq(name, "quantum.rand")) {
        var result: u32 = 0;
        asm volatile ("int $0x80"
            : [ret] "={eax}" (result),
            : [sys] "{eax}" (@as(u32, 55)),
        );
        return .{ .vtype = .int, .int_val = @intCast(result & 0xFF) };
    }
    if (common.streq(name, "quantum.entangle")) {
        var result: u32 = 0;
        asm volatile ("int $0x80"
            : [ret] "={eax}" (result),
            : [sys] "{eax}" (@as(u32, 57)),
        );
        const p_val = @as(i32, @intCast(result & 0xFF)) | (@as(i32, @intCast((result >> 8) & 0xFF)) << 8);
        return .{ .vtype = .int, .int_val = p_val };
    }
    if (common.streq(name, "quantum.info")) {
        // Try RDRAND: if syscall 55 returns non-deterministically, it's available
        return .{ .vtype = .string, .str_val = "use 'qrand --info' in shell" };
    }
    return null;
}
