// Calc command - evaluate expressions using Nova evaluator
const common = @import("common.zig");
const lexer = @import("../nova/lexer.zig");
const vm_mod = @import("../nova/vm.zig");
const nova_common = @import("../nova/common.zig");

pub fn execute(expr_ptr: [*]const u8, expr_len: u32) void {
    const expr = expr_ptr[0..expr_len];
    if (expr.len == 0) {
        common.printZ("Usage: calc <expression>\n");
        common.printZ("Example: calc (1 << 8) | 0xAA\n");
        return;
    }

    // 1. Append a semicolon if missing (Nova requires it for statements,
    // but here we might just evaluate it as an expression if we call evaluateExpression directly)
    // Actually, evaluateExpression doesn't need a semicolon.

    // 2. Tokenize
    var list = lexer.tokenize(expr);
    defer list.deinit();

    if (list.len <= 1) { // Just EOF
        return;
    }

    // 3. Initialize VM (minimal args)
    var vm = vm_mod.VM.init(list, &[_][]const u8{});

    // 4. Evaluate
    const result = vm.evaluateExpression();

    // 5. Check for errors
    if (vm.has_error) return;

    // 6. Print result
    common.printZ("= ");
    switch (result.vtype) {
        .int => {
            common.printNum(result.int_val);
            common.printZ(" (");
            var hex_buf: [16]u8 = undefined;
            common.printZ(nova_common.intToHex(@bitCast(result.int_val), &hex_buf));
            common.printZ(", 0b");
            var bin_buf: [34]u8 = undefined;
            common.printZ(fmt_bin_i32(result.int_val, &bin_buf));
            common.printZ(")");
        },
        .float => {
            var f_buf: [32]u8 = undefined;
            common.printZ(nova_common.floatToString(result.float_val, &f_buf));
        },
        .string => {
            common.printZ("\"");
            common.printZ(result.str_val);
            common.printZ("\"");
        },
        else => common.printZ("Unknown type"),
    }
    common.printZ("\n");
}

fn fmt_bin_i32(val: i32, buf: []u8) []const u8 {
    if (buf.len < 33) return "err";
    var v = @as(u32, @bitCast(val));
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        buf[31 - i] = if ((v & 1) != 0) '1' else '0';
        v >>= 1;
    }
    // Trim leading zeros but keep at least one
    var start: usize = 0;
    while (start < 31 and buf[start] == '0') : (start += 1) {}
    return buf[start..32];
}
