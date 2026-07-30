const common = @import("common.zig");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const hash_table = @import("hash_table.zig");
const arena_mod = @import("arena.zig");
const module = @import("module.zig");
const parser_mod = @import("parser.zig");
const checker_mod = @import("checker.zig");
const memory = @import("../memory.zig");
const shell = @import("../shell.zig");
const fat = @import("../drivers/fat.zig");
const ata = @import("../drivers/ata.zig");
const global_common = @import("../commands/common.zig");
const keyboard = @import("../keyboard_isr.zig");
const vga = @import("../drivers/vga.zig");
const math_mod = @import("modules/math.zig");
const sys_mod = @import("modules/sys.zig");
const speaker_mod = @import("modules/speaker.zig");
const quantum_mod = @import("modules/quantum.zig");
const user = @import("../user.zig");

const Node = ast.Node;
const VariableValue = hash_table.VariableValue;
const VariableType = hash_table.VariableType;

const Scope = struct {
    table: hash_table.HashTable,
    parent: ?*Scope,
};

pub const VM = struct {
    arena: *arena_mod.Arena,
    program: *Node,
    prog_ip: usize,
    globals: hash_table.HashTable,
    functions: hash_table.HashTable,
    scope: *Scope,
    exit_flag: bool,
    has_error: bool,
    break_flag: bool,
    continue_flag: bool,
    return_flag: bool,
    return_value: VariableValue,
    cache: module.ModuleCache,
    angle_mode: common.AngleMode,
    current_file: []const u8,
    script_args: []const []const u8,
    is_math_loaded: bool,
    is_sys_loaded: bool,
    is_speaker_loaded: bool,
    is_quantum_loaded: bool,
    repl_mode: bool,

    pub fn init(program: *Node, arena: *arena_mod.Arena, args: []const []const u8) VM {
        const scope_ptr = user.user_malloc(@sizeOf(Scope)) orelse unreachable;
        const scope: *Scope = @ptrCast(@alignCast(scope_ptr));
        scope.* = .{
            .table = hash_table.HashTable.init(16),
            .parent = null,
        };

        var vm = VM{
            .arena = arena,
            .program = program,
            .prog_ip = 0,
            .globals = hash_table.HashTable.init(32),
            .functions = hash_table.HashTable.init(16),
            .scope = scope,
            .exit_flag = false,
            .has_error = false,
            .break_flag = false,
            .continue_flag = false,
            .return_flag = false,
            .return_value = .{ .vtype = .int, .int_val = 0 },
            .cache = module.ModuleCache.init(),
            .angle_mode = .DEG,
            .current_file = "main.nv",
            .script_args = args,
            .is_math_loaded = false,
            .is_sys_loaded = false,
            .is_speaker_loaded = false,
            .is_quantum_loaded = false,
            .repl_mode = false,
        };

        vm.globals.put("rad", .{ .vtype = .string, .str_val = "rad" });
        vm.globals.put("deg", .{ .vtype = .string, .str_val = "deg" });

        return vm;
    }

    pub fn run(self: *VM) void {
        self.exec(self.program);
    }

    pub fn exec(self: *VM, node: *Node) void {
        if (self.exit_flag) return;

        switch (node.node_type) {
            .program => {
                var i: usize = 0;
                while (i < node.stmt_count and !self.exit_flag) : (i += 1) {
                    if (keyboard.check_ctrl_c()) {
                        common.printZ("\nInterrupted by Ctrl+C\n");
                        self.exit_flag = true;
                        return;
                    }
                    self.exec(node.stmts.?[i]);
                }
            },
            .block => {
                self.pushScope();
                var i: usize = 0;
                while (i < node.stmt_count and !self.exit_flag and !self.break_flag and !self.continue_flag and !self.return_flag) : (i += 1) {
                    if (keyboard.check_ctrl_c()) {
                        common.printZ("\nInterrupted by Ctrl+C\n");
                        self.exit_flag = true;
                        return;
                    }
                    self.exec(node.stmts.?[i]);
                }
                self.popScope();
            },
            .var_decl => {
                const val = if (node.left) |initial| self.eval(initial) else self.defaultValue(node.decl_type);
                self.scope.table.put(node.str_val, val);
            },
            .assign => {
                const val = if (node.left) |expr| self.eval(expr) else VariableValue{ .vtype = .int, .int_val = 0 };
                self.updateVar(node.str_val, val);
            },
            .func_call => {
                const result = self.execFuncCall(node);
                if (self.repl_mode and !common.streq(node.str_val, "print")) {
                    self.printValue(result);
                }
            },
            .if_stmt => {
                const cond = if (node.left) |c| self.eval(c) else VariableValue{ .vtype = .int, .int_val = 0 };
                if (cond.int_val != 0) {
                    if (node.right) |then_block| self.exec(then_block);
                } else if (node.stmt_count > 0 and node.stmts != null) {
                    self.exec(node.stmts.?[0]);
                }
            },
            .while_stmt => {
                const start_node = node;
                while (!self.exit_flag) {
                    if (keyboard.check_ctrl_c()) {
                        common.printZ("\nInterrupted by Ctrl+C\n");
                        self.exit_flag = true;
                        return;
                    }
                    const cond = if (start_node.left) |c| self.eval(c) else VariableValue{ .vtype = .int, .int_val = 0 };
                    if (cond.int_val != 0) {
                        if (start_node.right) |body| self.exec(body);
                        if (self.break_flag) {
                            self.break_flag = false;
                            break;
                        }
                        if (self.exit_flag or self.return_flag) return;
                        self.continue_flag = false;
                    } else {
                        break;
                    }
                }
            },
            .for_stmt => {
                self.pushScope();
                if (node.stmt_count >= 1 and node.stmts != null) {
                    const initial = node.stmts.?[0];
                    self.exec(initial);
                }
                while (!self.exit_flag) {
                    if (keyboard.check_ctrl_c()) {
                        common.printZ("\nInterrupted by Ctrl+C\n");
                        self.exit_flag = true;
                        return;
                    }
                    const cond = if (node.left) |c| self.eval(c) else VariableValue{ .vtype = .int, .int_val = 1 };
                    if (cond.int_val == 0) break;
                    if (node.right) |body| self.exec(body);
                    if (self.break_flag) {
                        self.break_flag = false;
                        break;
                    }
                    if (self.exit_flag or self.return_flag) break;
                    self.continue_flag = false;
                    if (node.stmt_count >= 2 and node.stmts != null) {
                        const incr = node.stmts.?[1];
                        self.exec(incr);
                    }
                }
                self.popScope();
            },
            .func_def => {
                self.functions.put(node.str_val, .{
                    .vtype = .function,
                    .func_ptr = @intFromPtr(node),
                });
            },
            .return_stmt => {
                self.return_value = if (node.left) |expr| self.eval(expr) else VariableValue{ .vtype = .int, .int_val = 0 };
                self.return_flag = true;
            },
            .import_stmt => {
                self.execImport(node);
            },
            .break_stmt => {
                self.break_flag = true;
            },
            .continue_stmt => {
                self.continue_flag = true;
            },
            else => {
                _ = self.eval(node);
            },
        }
    }

    pub fn eval(self: *VM, node: *Node) VariableValue {
        switch (node.node_type) {
            .int_lit => return .{ .vtype = .int, .int_val = node.int_val },
            .float_lit => return .{ .vtype = .float, .float_val = node.float_val },
            .str_lit => return .{ .vtype = .string, .str_val = node.str_val },
            .ident => return self.lookupVar(node.str_val),
            .bin_op => return self.evalBinOp(node),
            .unary_op => return self.evalUnaryOp(node),
            .func_call => return self.execFuncCall(node),
            .assign => {
                const val = if (node.left) |expr| self.eval(expr) else VariableValue{ .vtype = .int, .int_val = 0 };
                self.updateVar(node.str_val, val);
                return val;
            },
            else => return .{ .vtype = .int, .int_val = 0 },
        }
    }

    fn evalBinOp(self: *VM, node: *Node) VariableValue {
        const left = if (node.left) |l| self.eval(l) else return .{ .vtype = .int, .int_val = 0 };
        const right = if (node.right) |r| self.eval(r) else return .{ .vtype = .int, .int_val = 0 };

        switch (node.bin_op) {
            .add => {
                if (left.vtype == .int and right.vtype == .int) {
                    return .{ .vtype = .int, .int_val = left.int_val + right.int_val };
                }
                if (left.vtype == .float or right.vtype == .float) {
                    const lf = if (left.vtype == .float) left.float_val else @as(f32, @floatFromInt(left.int_val));
                    const rf = if (right.vtype == .float) right.float_val else @as(f32, @floatFromInt(right.int_val));
                    return .{ .vtype = .float, .float_val = lf + rf };
                }
                if (left.vtype == .string and right.vtype == .string) {
                    const total = left.str_val.len + right.str_val.len;
                    const buf_ptr = user.user_malloc(total) orelse return left;
                    const buf = buf_ptr[0..total];
                    @memcpy(buf[0..left.str_val.len], left.str_val);
                    @memcpy(buf[left.str_val.len..], right.str_val);
                    return .{ .vtype = .string, .str_val = buf };
                }
                return left;
            },
            .sub => {
                if (left.vtype == .int and right.vtype == .int) return .{ .vtype = .int, .int_val = left.int_val - right.int_val };
                const lf = if (left.vtype == .float) left.float_val else @as(f32, @floatFromInt(left.int_val));
                const rf = if (right.vtype == .float) right.float_val else @as(f32, @floatFromInt(right.int_val));
                return .{ .vtype = .float, .float_val = lf - rf };
            },
            .mul => {
                if (left.vtype == .int and right.vtype == .int) return .{ .vtype = .int, .int_val = left.int_val * right.int_val };
                const lf = if (left.vtype == .float) left.float_val else @as(f32, @floatFromInt(left.int_val));
                const rf = if (right.vtype == .float) right.float_val else @as(f32, @floatFromInt(right.int_val));
                return .{ .vtype = .float, .float_val = lf * rf };
            },
            .div => {
                if (left.vtype == .int and right.vtype == .int) {
                    if (right.int_val == 0) return left;
                    return .{ .vtype = .int, .int_val = @divTrunc(left.int_val, right.int_val) };
                }
                const lf = if (left.vtype == .float) left.float_val else @as(f32, @floatFromInt(left.int_val));
                const rf = if (right.vtype == .float) right.float_val else @as(f32, @floatFromInt(right.int_val));
                if (rf == 0) return .{ .vtype = .float, .float_val = lf };
                return .{ .vtype = .float, .float_val = lf / rf };
            },
            .mod => {
                if (left.vtype == .int and right.vtype == .int) {
                    if (right.int_val == 0) return left;
                    return .{ .vtype = .int, .int_val = @rem(left.int_val, right.int_val) };
                }
                return left;
            },
            .eq => {
                if (left.vtype == .int and right.vtype == .int) return .{ .vtype = .int, .int_val = if (left.int_val == right.int_val) 1 else 0 };
                if (left.vtype == .float or right.vtype == .float) {
                    const lf = if (left.vtype == .float) left.float_val else @as(f32, @floatFromInt(left.int_val));
                    const rf = if (right.vtype == .float) right.float_val else @as(f32, @floatFromInt(right.int_val));
                    return .{ .vtype = .int, .int_val = if (lf == rf) 1 else 0 };
                }
                if (left.vtype == .string and right.vtype == .string) {
                    return .{ .vtype = .int, .int_val = if (common.streq(left.str_val, right.str_val)) 1 else 0 };
                }
                return .{ .vtype = .int, .int_val = 0 };
            },
            .neq => {
                if (left.vtype == .int and right.vtype == .int) return .{ .vtype = .int, .int_val = if (left.int_val != right.int_val) 1 else 0 };
                if (left.vtype == .float or right.vtype == .float) {
                    const lf = if (left.vtype == .float) left.float_val else @as(f32, @floatFromInt(left.int_val));
                    const rf = if (right.vtype == .float) right.float_val else @as(f32, @floatFromInt(right.int_val));
                    return .{ .vtype = .int, .int_val = if (lf != rf) 1 else 0 };
                }
                if (left.vtype == .string and right.vtype == .string) {
                    return .{ .vtype = .int, .int_val = if (!common.streq(left.str_val, right.str_val)) 1 else 0 };
                }
                return .{ .vtype = .int, .int_val = 1 };
            },
            .lt => {
                if (left.vtype == .int and right.vtype == .int) return .{ .vtype = .int, .int_val = if (left.int_val < right.int_val) 1 else 0 };
                const lf = if (left.vtype == .float) left.float_val else @as(f32, @floatFromInt(left.int_val));
                const rf = if (right.vtype == .float) right.float_val else @as(f32, @floatFromInt(right.int_val));
                return .{ .vtype = .int, .int_val = if (lf < rf) 1 else 0 };
            },
            .gt => {
                if (left.vtype == .int and right.vtype == .int) return .{ .vtype = .int, .int_val = if (left.int_val > right.int_val) 1 else 0 };
                const lf = if (left.vtype == .float) left.float_val else @as(f32, @floatFromInt(left.int_val));
                const rf = if (right.vtype == .float) right.float_val else @as(f32, @floatFromInt(right.int_val));
                return .{ .vtype = .int, .int_val = if (lf > rf) 1 else 0 };
            },
            .le => {
                const eq = if (left.vtype == .int and right.vtype == .int) left.int_val == right.int_val else false;
                const lt = blk: {
                    if (left.vtype == .int and right.vtype == .int) break :blk left.int_val < right.int_val;
                    const lf = if (left.vtype == .float) left.float_val else @as(f32, @floatFromInt(left.int_val));
                    const rf = if (right.vtype == .float) right.float_val else @as(f32, @floatFromInt(right.int_val));
                    break :blk lf < rf;
                };
                return .{ .vtype = .int, .int_val = if (eq or lt) 1 else 0 };
            },
            .ge => {
                const eq = if (left.vtype == .int and right.vtype == .int) left.int_val == right.int_val else false;
                const gt = blk: {
                    if (left.vtype == .int and right.vtype == .int) break :blk left.int_val > right.int_val;
                    const lf = if (left.vtype == .float) left.float_val else @as(f32, @floatFromInt(left.int_val));
                    const rf = if (right.vtype == .float) right.float_val else @as(f32, @floatFromInt(right.int_val));
                    break :blk lf > rf;
                };
                return .{ .vtype = .int, .int_val = if (eq or gt) 1 else 0 };
            },
            .bit_and => {
                if (left.vtype == .int and right.vtype == .int) return .{ .vtype = .int, .int_val = left.int_val & right.int_val };
                return left;
            },
            .bit_or => {
                if (left.vtype == .int and right.vtype == .int) return .{ .vtype = .int, .int_val = left.int_val | right.int_val };
                return left;
            },
            .bit_xor => {
                if (left.vtype == .int and right.vtype == .int) return .{ .vtype = .int, .int_val = left.int_val ^ right.int_val };
                return left;
            },
            .shl => {
                if (left.vtype == .int and right.vtype == .int) return .{ .vtype = .int, .int_val = left.int_val << @intCast(@as(u5, @truncate(@as(u32, @bitCast(right.int_val))))) };
                return left;
            },
            .shr => {
                if (left.vtype == .int and right.vtype == .int) return .{ .vtype = .int, .int_val = left.int_val >> @intCast(@as(u5, @truncate(@as(u32, @bitCast(right.int_val))))) };
                return left;
            },
        }
    }

    fn evalUnaryOp(self: *VM, node: *Node) VariableValue {
        const val = if (node.left) |op| self.eval(op) else return .{ .vtype = .int, .int_val = 0 };
        switch (node.unary_op) {
            .neg => {
                if (val.vtype == .int) return .{ .vtype = .int, .int_val = -val.int_val };
                if (val.vtype == .float) return .{ .vtype = .float, .float_val = -val.float_val };
                return val;
            },
            .bit_not => {
                if (val.vtype == .int) return .{ .vtype = .int, .int_val = ~val.int_val };
                return val;
            },
        }
    }

    fn execFuncCall(self: *VM, node: *Node) VariableValue {
        const name = node.str_val;

        // Evaluate arguments
        var args: [8]VariableValue = undefined;
        var arg_count: usize = 0;
        for (0..node.stmt_count) |i| {
            args[arg_count] = self.eval(node.stmts.?[i]);
            arg_count += 1;
        }
        const arg_slice = args[0..arg_count];

        // Dispatch builtins
        if (common.streq(name, "print")) {
            if (arg_count >= 1) self.printValue(arg_slice[0]);
            common.printBuf("\n");
            return .{ .vtype = .string, .str_val = "" };
        }
        if (common.streq(name, "exit")) {
            self.exit_flag = true;
            return .{ .vtype = .string, .str_val = "" };
        }
        if (common.streq(name, "len")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .string) return .{ .vtype = .int, .int_val = @intCast(arg_slice[0].str_val.len) };
            return .{ .vtype = .int, .int_val = 0 };
        }
        if (common.streq(name, "int")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .string) return .{ .vtype = .int, .int_val = common.parseInt(arg_slice[0].str_val) };
            if (arg_count >= 1) return arg_slice[0];
            return .{ .vtype = .int, .int_val = 0 };
        }
        if (common.streq(name, "str")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .int) {
                var buf: [16]u8 = undefined;
                const s = common.intToString(arg_slice[0].int_val, &buf);
                const copy_ptr = user.user_malloc(s.len) orelse return .{ .vtype = .string, .str_val = "" };
                const copy = copy_ptr[0..s.len];
                @memcpy(copy, s);
                return .{ .vtype = .string, .str_val = copy };
            }
            if (arg_count >= 1) return arg_slice[0];
            return .{ .vtype = .string, .str_val = "" };
        }
        if (common.streq(name, "argc")) {
            return .{ .vtype = .int, .int_val = @intCast(self.script_args.len) };
        }
        if (common.streq(name, "args")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .int) {
                const idx = arg_slice[0].int_val;
                if (idx >= 0 and idx < self.script_args.len) {
                    return .{ .vtype = .string, .str_val = self.script_args[@intCast(idx)] };
                }
            }
            return .{ .vtype = .string, .str_val = "" };
        }
        if (common.streq(name, "input")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .string) {
                common.printBuf(arg_slice[0].str_val);
            }
            var buf_ptr = user.user_malloc(128) orelse return .{ .vtype = .string, .str_val = "" };
            var len: usize = 0;
            while (len < 127) {
                const key = keyboard.keyboard_wait_char();
                if (key == 10 or key == 13) {
                    common.printBuf("\n");
                    break;
                } else if (key == 8 or key == 127) {
                    if (len > 0) {
                        len -= 1;
                        common.printZ("\x08 \x08");
                    }
                } else if (key >= 32 and key <= 126) {
                    buf_ptr[len] = key;
                    len += 1;
                    common.print_char(key);
                }
            }
            return .{ .vtype = .string, .str_val = buf_ptr[0..len] };
        }
        if (common.streq(name, "format_size")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .int) {
                const b = @as(u64, @intCast(arg_slice[0].int_val));
                const buf_ptr = user.user_malloc(32) orelse return .{ .vtype = .string, .str_val = "" };
                const buf = buf_ptr[0..32];
                var res: []const u8 = "";
                if (b < 1024) {
                    res = common.intToString(@intCast(b), buf);
                    const final = buf[0 .. res.len + 2];
                    common.copy(buf[res.len..], " B");
                    return .{ .vtype = .string, .str_val = final };
                } else if (b < 1024 * 1024) {
                    res = common.intToString(@intCast(b / 1024), buf);
                    const final = buf[0 .. res.len + 3];
                    common.copy(buf[res.len..], " KB");
                    return .{ .vtype = .string, .str_val = final };
                } else if (b < 1024 * 1024 * 1024) {
                    res = common.intToString(@intCast(b / (1024 * 1024)), buf);
                    const final = buf[0 .. res.len + 3];
                    common.copy(buf[res.len..], " MB");
                    return .{ .vtype = .string, .str_val = final };
                } else {
                    res = common.intToString(@intCast(b / (1024 * 1024 * 1024)), buf);
                    const final = buf[0 .. res.len + 3];
                    common.copy(buf[res.len..], " GB");
                    return .{ .vtype = .string, .str_val = final };
                }
            }
            return .{ .vtype = .string, .str_val = "0 B" };
        }
        if (common.streq(name, "format")) {
            if (arg_count >= 2 and arg_slice[1].vtype == .string) {
                const fmt = arg_slice[1].str_val;
                if (common.streq(fmt, "int") or common.streq(fmt, "str") or common.streq(fmt, "string")) {
                    if (arg_slice[0].vtype == .int) {
                        var buf: [16]u8 = undefined;
                        const s = common.intToString(arg_slice[0].int_val, &buf);
                        const copy_ptr = user.user_malloc(s.len) orelse return .{ .vtype = .string, .str_val = "" };
                        const copy = copy_ptr[0..s.len];
                        @memcpy(copy, s);
                        return .{ .vtype = .string, .str_val = copy };
                    }
                    return arg_slice[0];
                }
                if (common.streq(fmt, "size")) {
                    if (arg_slice[0].vtype == .int) {
                        const b = @as(u64, @intCast(arg_slice[0].int_val));
                        const buf_ptr = user.user_malloc(32) orelse return .{ .vtype = .string, .str_val = "" };
                        const buf = buf_ptr[0..32];
                        if (b < 1024) {
                            const r = common.intToString(@intCast(b), buf);
                            const f = buf[0 .. r.len + 2];
                            common.copy(buf[r.len..], " B");
                            return .{ .vtype = .string, .str_val = f };
                        } else if (b < 1024 * 1024) {
                            const r = common.intToString(@intCast(b / 1024), buf);
                            const f = buf[0 .. r.len + 3];
                            common.copy(buf[r.len..], " KB");
                            return .{ .vtype = .string, .str_val = f };
                        } else if (b < 1024 * 1024 * 1024) {
                            const r = common.intToString(@intCast(b / (1024 * 1024)), buf);
                            const f = buf[0 .. r.len + 3];
                            common.copy(buf[r.len..], " MB");
                            return .{ .vtype = .string, .str_val = f };
                        } else {
                            const r = common.intToString(@intCast(b / (1024 * 1024 * 1024)), buf);
                            const f = buf[0 .. r.len + 3];
                            common.copy(buf[r.len..], " GB");
                            return .{ .vtype = .string, .str_val = f };
                        }
                    }
                }
                if (common.streq(fmt, "hex")) {
                    if (arg_slice[0].vtype == .int) {
                        var buf: [16]u8 = undefined;
                        const s = common.intToHex(@intCast(arg_slice[0].int_val), &buf);
                        const copy_ptr = user.user_malloc(s.len) orelse return .{ .vtype = .string, .str_val = "" };
                        const copy = copy_ptr[0..s.len];
                        @memcpy(copy, s);
                        return .{ .vtype = .string, .str_val = copy };
                    }
                }
            }
            return if (arg_count >= 1) arg_slice[0] else .{ .vtype = .int, .int_val = 0 };
        }
        if (common.streq(name, "split")) {
            if (arg_count >= 3 and arg_slice[0].vtype == .string and arg_slice[1].vtype == .string and arg_slice[2].vtype == .int) {
                const s = arg_slice[0].str_val;
                const sep = arg_slice[1].str_val;
                const target_idx = arg_slice[2].int_val;
                var current_idx: i32 = 0;
                var start: usize = 0;
                var i: usize = 0;
                while (i < s.len) {
                    if (common.startsWith(s[i..], sep)) {
                        if (current_idx == target_idx) return .{ .vtype = .string, .str_val = s[start..i] };
                        current_idx += 1;
                        i += sep.len;
                        start = i;
                    } else {
                        i += 1;
                    }
                }
                if (current_idx == target_idx) return .{ .vtype = .string, .str_val = s[start..] };
            }
            return .{ .vtype = .string, .str_val = "" };
        }

        // File operations
        if (common.streq(name, "read")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    var buf_ptr = user.user_malloc(4096) orelse return .{ .vtype = .string, .str_val = "" };
                    const len = fat.read_file(drive, bpb, global_common.current_dir_cluster, arg_slice[0].str_val, buf_ptr);
                    if (len > 0) return .{ .vtype = .string, .str_val = buf_ptr[0..@intCast(len)] };
                    user.user_free(buf_ptr);
                }
            }
            return .{ .vtype = .string, .str_val = "" };
        }
        if (common.streq(name, "write")) {
            if (arg_count >= 2 and arg_slice[0].vtype == .string and arg_slice[1].vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.write_file(drive, bpb, global_common.current_dir_cluster, arg_slice[0].str_val, arg_slice[1].str_val)) {
                        return .{ .vtype = .string, .str_val = "Data written" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Write failed" };
        }
        if (common.streq(name, "delete") or common.streq(name, "remove") or common.streq(name, "rm")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.delete_file(drive, bpb, global_common.current_dir_cluster, arg_slice[0].str_val)) {
                        return .{ .vtype = .string, .str_val = "Removed" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Could not remove" };
        }
        if (common.streq(name, "rename") or common.streq(name, "mv")) {
            if (arg_count >= 2 and arg_slice[0].vtype == .string and arg_slice[1].vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.rename_file(drive, bpb, global_common.current_dir_cluster, arg_slice[0].str_val, arg_slice[1].str_val)) {
                        return .{ .vtype = .string, .str_val = "Renamed" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Could not rename" };
        }
        if (common.streq(name, "copy") or common.streq(name, "cp")) {
            if (arg_count >= 2 and arg_slice[0].vtype == .string and arg_slice[1].vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.copy_file(drive, bpb, global_common.current_dir_cluster, arg_slice[0].str_val, arg_slice[1].str_val)) {
                        return .{ .vtype = .string, .str_val = "Copied" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Could not copy" };
        }
        if (common.streq(name, "exists")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.resolve_full_path(drive, bpb, global_common.current_dir_cluster, global_common.current_path[0..global_common.current_path_len], arg_slice[0].str_val)) |_| {
                        return .{ .vtype = .int, .int_val = 1 };
                    }
                }
            }
            return .{ .vtype = .int, .int_val = 0 };
        }
        if (common.streq(name, "mkdir")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.create_directory(drive, bpb, global_common.current_dir_cluster, arg_slice[0].str_val)) {
                        return .{ .vtype = .string, .str_val = "Directory created" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Could not create directory" };
        }
        if (common.streq(name, "size")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.find_entry(drive, bpb, global_common.current_dir_cluster, arg_slice[0].str_val)) |entry| {
                        return .{ .vtype = .int, .int_val = @intCast(entry.file_size) };
                    }
                }
            }
            return .{ .vtype = .int, .int_val = -1 };
        }
        if (common.streq(name, "create_file")) {
            if (arg_count >= 1 and arg_slice[0].vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.write_file(drive, bpb, global_common.current_dir_cluster, arg_slice[0].str_val, "")) {
                        return .{ .vtype = .string, .str_val = "File created" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Could not create file" };
        }

        // Module functions
        if (common.startsWith(name, "math.")) {
            if (!self.is_math_loaded) {
                self.reportError("Module 'math' not imported");
                return .{ .vtype = .int, .int_val = 0 };
            }
            if (math_mod.handleMath(self, name, arg_slice)) |res| return res;
            self.reportError("Unknown math function");
            return .{ .vtype = .int, .int_val = 0 };
        }
        if (common.startsWith(name, "sys.")) {
            if (!self.is_sys_loaded) {
                self.reportError("Module 'sys' not imported");
                return .{ .vtype = .int, .int_val = 0 };
            }
            if (sys_mod.handleSys(self, name, arg_slice)) |res| return res;
            self.reportError("Unknown sys function");
            return .{ .vtype = .int, .int_val = 0 };
        }
        if (common.startsWith(name, "speaker.")) {
            if (!self.is_speaker_loaded) {
                self.reportError("Module 'speaker' not imported");
                return .{ .vtype = .int, .int_val = 0 };
            }
            if (speaker_mod.handleSpeaker(self, name, arg_slice)) |res| return res;
            self.reportError("Unknown speaker function");
            return .{ .vtype = .int, .int_val = 0 };
        }
        if (common.startsWith(name, "quantum.")) {
            if (!self.is_quantum_loaded) {
                self.reportError("Module 'quantum' not imported");
                return .{ .vtype = .int, .int_val = 0 };
            }
            if (quantum_mod.handleQuantum(self, name, arg_slice)) |res| return res;
            self.reportError("Unknown quantum function");
            return .{ .vtype = .int, .int_val = 0 };
        }

        // User-defined function
        if (self.functions.get(name)) |func| {
            if (func.vtype == .function) {
                const func_node: *Node = @ptrFromInt(func.func_ptr);
                return self.execUserFunc(func_node, arg_slice);
            }
        }

        self.reportError("Undefined function: ");
        common.printZ(name);
        common.printZ("\n");
        return .{ .vtype = .int, .int_val = 0 };
    }

    fn execUserFunc(self: *VM, func_node: *Node, args: []const VariableValue) VariableValue {
        const prev_scope = self.scope;
        const prev_return = self.return_value;
        const prev_return_flag = self.return_flag;

        self.pushScope();

        // Bind parameters
        const param_count = func_node.stmt_count;
        var i: usize = 0;
        while (i < param_count and i < args.len) : (i += 1) {
            if (func_node.stmts) |params| {
                self.scope.table.put(params[i].str_val, args[i]);
            }
        }

        // Execute body
        if (func_node.right) |body| {
            self.return_flag = false;
            self.return_value = .{ .vtype = .int, .int_val = 0 };
            self.exec(body);
        }

        const result = self.return_value;
        self.popScope();
        self.scope = prev_scope;
        self.return_value = prev_return;
        self.return_flag = prev_return_flag;

        return result;
    }

    fn execImport(self: *VM, node: *Node) void {
        const path = node.str_val;

        // Built-in modules
        if (common.streq(path, "math")) {
            self.is_math_loaded = true;
            return;
        }
        if (common.streq(path, "sys")) {
            self.is_sys_loaded = true;
            return;
        }
        if (common.streq(path, "speaker")) {
            self.is_speaker_loaded = true;
            return;
        }
        if (common.streq(path, "quantum")) {
            self.is_quantum_loaded = true;
            return;
        }

        // File imports
        var path_buf: [128]u8 = undefined;
        const resolved = module.ModuleCache.resolvePath(self.current_file, path, &path_buf);

        if (self.cache.isLoaded(resolved)) return;

        const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            var found = false;
            var current_dir_cluster_val = global_common.current_dir_cluster;

            if (fat.find_entry(drive, bpb, current_dir_cluster_val, resolved)) |_| {
                found = true;
            } else {
                if (fat.resolve_full_path(drive, bpb, 0, "/", ".SYSTEM/NOVA/MOD")) |sys_mod_res| {
                    if (sys_mod_res.is_dir) {
                        if (fat.find_entry(drive, bpb, sys_mod_res.cluster, resolved)) |_| {
                            found = true;
                            current_dir_cluster_val = sys_mod_res.cluster;
                        }
                    }
                }
            }

            if (found) {
                var script_buffer: [4096]u8 = [_]u8{0} ** 4096;
                const bytes_read = fat.read_file(drive, bpb, current_dir_cluster_val, resolved, &script_buffer);
                if (bytes_read > 0) {
                    const source = script_buffer[0..@intCast(bytes_read)];
                    const old_file = self.current_file;

                    // Tokenize and parse imported source
                    const tokens = lexer.tokenize(source);
                    var temp_arena = arena_mod.Arena.init();
                    var parser = parser_mod.Parser.init(tokens, &temp_arena);
                    const import_prog = parser.parseProgram();
                    const import_ok = !parser.had_error;

                    if (import_ok) {
                        if (import_prog) |prog| {
                            var checker = checker_mod.Checker.init();
                            checker.check(prog);
                            const check_ok = !checker.had_error;

                            if (check_ok) {
                                self.current_file = resolved;
                                self.cache.markLoaded(resolved);
                                self.exec(prog);
                                self.current_file = old_file;
                            }
                        }
                    }

                    temp_arena.reset();
                }
            }
        }
    }

    pub fn evaluateExpression(_: *VM) VariableValue {
        // Module compatibility stub — should not be called in new code
        return .{ .vtype = .int, .int_val = 0 };
    }

    fn pushScope(self: *VM) void {
        const ptr = user.user_malloc(@sizeOf(Scope)) orelse return;
        const scope: *Scope = @ptrCast(@alignCast(ptr));
        scope.* = .{
            .table = hash_table.HashTable.init(8),
            .parent = self.scope,
        };
        self.scope = scope;
    }

    fn popScope(self: *VM) void {
        if (self.scope.parent) |parent| {
            self.scope.table.deinit();
            user.user_free(@ptrCast(self.scope));
            self.scope = parent;
        }
    }

    fn lookupVar(self: *VM, name: []const u8) VariableValue {
        var s: ?*Scope = self.scope;
        while (s) |scope| {
            if (scope.table.get(name)) |v| return v;
            s = scope.parent;
        }
        if (self.globals.get(name)) |v| return v;
        return .{ .vtype = .int, .int_val = 0 };
    }

    fn updateVar(self: *VM, name: []const u8, val: VariableValue) void {
        var s: ?*Scope = self.scope;
        while (s) |scope| {
            if (scope.table.get(name)) |_| {
                scope.table.put(name, val);
                return;
            }
            s = scope.parent;
        }
        if (self.globals.get(name)) |_| {
            self.globals.put(name, val);
            return;
        }
        self.scope.table.put(name, val);
    }

    fn defaultValue(self: *VM, t: ?VariableType) VariableValue {
        _ = self;
        return switch (t orelse .int) {
            .int => .{ .vtype = .int, .int_val = 0 },
            .float => .{ .vtype = .float, .float_val = 0.0 },
            .string => .{ .vtype = .string, .str_val = "" },
            .function => .{ .vtype = .int, .int_val = 0 },
        };
    }

    fn printValue(self: *VM, val: VariableValue) void {
        _ = self;
        switch (val.vtype) {
            .string => {
                if (val.str_val.len > 0) common.printBuf(val.str_val);
            },
            .float => {
                var buf: [32]u8 = undefined;
                const s = common.floatToString(val.float_val, &buf);
                common.printBuf(s);
            },
            .int => {
                var buf: [16]u8 = undefined;
                const s = common.intToString(val.int_val, &buf);
                common.printBuf(s);
            },
            .function => {
                common.printZ("<function>");
            },
        }
    }

    fn reportError(self: *VM, msg: []const u8) void {
        common.printZ("Runtime Error: ");
        common.printZ(msg);
        common.printZ("\n");
        self.exit_flag = true;
        self.has_error = true;
    }
};
