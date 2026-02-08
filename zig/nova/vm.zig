// Nova Language - Virtual Machine
const common = @import("common.zig");
const lexer = @import("lexer.zig");
const hash_table = @import("hash_table.zig");
const module = @import("module.zig");
const memory = @import("../memory.zig");
const shell = @import("../shell.zig");
const fat = @import("../drivers/fat.zig");
const ata = @import("../drivers/ata.zig");
const global_common = @import("../commands/common.zig");
const keyboard = @import("../keyboard_isr.zig");
const vga = @import("../drivers/vga.zig");

pub const VM = struct {
    tokens: lexer.TokenList,
    ip: usize = 0,
    globals: hash_table.HashTable,
    functions: hash_table.HashTable,
    current_scope: *Scope,
    exit_flag: bool = false,
    break_flag: bool = false,
    continue_flag: bool = false,
    cache: module.ModuleCache,
    angle_mode: AngleMode = .DEG,
    current_file: []const u8 = "main.nv",
    script_args: []const []const u8 = &[_][]const u8{},
    repl_mode: bool = false,

    pub const Scope = struct {
        table: hash_table.HashTable,
        parent: ?*Scope,
    };

    pub const AngleMode = enum {
        DEG,
        RAD,
    };

    pub fn reportError(self: *VM, msg: []const u8) void {
        const line = if (self.ip < self.tokens.len) self.tokens.tokens[self.ip].line else 0;
        common.printZ("Runtime Error in ");
        common.printZ(self.current_file);
        common.printZ(" at line ");
        var buf: [16]u8 = undefined;
        common.printZ(common.intToString(@intCast(line), &buf));
        common.printZ(": ");
        common.printZ(msg);
        common.printZ("\n");
        self.exit_flag = true;
    }

    pub fn init(tokens: lexer.TokenList, args: []const []const u8) VM {
        var vm = VM{
            .tokens = tokens,
            .ip = 0,
            .globals = hash_table.HashTable.init(32),
            .functions = hash_table.HashTable.init(16),
            .current_scope = undefined, // Set below
            .cache = module.ModuleCache.init(),
            .script_args = args,
        };

        const scope_ptr = memory.heap.alloc(@sizeOf(Scope)) orelse unreachable;
        const scope: *Scope = @ptrCast(@alignCast(scope_ptr));
        scope.* = .{
            .table = hash_table.HashTable.init(16),
            .parent = null,
        };
        vm.current_scope = scope;

        // Add built-in constants for easier usage
        vm.globals.put("rad", .{ .vtype = .string, .str_val = "rad" });
        vm.globals.put("deg", .{ .vtype = .string, .str_val = "deg" });

        return vm;
    }

    pub fn run(self: *VM) void {
        while (self.ip < self.tokens.len and !self.exit_flag) {
            if (keyboard.check_ctrl_c()) {
                common.printZ("\nInterrupted by Ctrl+C\n");
                self.exit_flag = true;
                break;
            }
            const token = self.tokens.tokens[self.ip];

            switch (token.ttype) {
                .DEF => self.handleDef(),
                .IMPORT => self.handleImport(),
                .IF => self.handleIf(),
                .WHILE => self.handleWhile(),
                .SET => self.handleSet(),
                .IDENTIFIER => self.handleAssignmentOrCall(),
                .L_BRACE => self.ip += 1, // Skip {
                .R_BRACE => {
                    // This happens at end of blocks if not handled by handleIf/while
                    self.ip += 1;
                },
                .SEMICOLON => self.ip += 1,
                .EOF => break,
                else => {
                    // Skip or error
                    self.ip += 1;
                },
            }
        }
    }

    fn handleDef(self: *VM) void {
        self.ip += 1; // skip def
        if (self.ip >= self.tokens.len) return;

        const name_token = self.tokens.tokens[self.ip];
        if (name_token.ttype != .IDENTIFIER) return;

        self.ip += 1; // skip name
        while (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype != .L_BRACE) : (self.ip += 1) {}

        // Value is the IP of the first token after def name
        self.functions.put(name_token.value, .{
            .vtype = .function,
            .func_ptr = self.ip,
        });

        // Skip until matching }
        var depth: i32 = 0;
        while (self.ip < self.tokens.len) : (self.ip += 1) {
            const t = self.tokens.tokens[self.ip];
            if (t.ttype == .L_BRACE) depth += 1;
            if (t.ttype == .R_BRACE) {
                depth -= 1;
                if (depth == 0) {
                    self.ip += 1;
                    break;
                }
            }
        }
    }

    fn handleIf(self: *VM) void {
        self.ip += 1; // skip if
        const condition = self.evaluateExpression();

        if (condition.int_val != 0) {
            // Execute block (we just continue into it)
            if (self.tokens.tokens[self.ip].ttype == .L_BRACE) {
                self.ip += 1;
            }
        } else {
            // Skip block
            self.skipBlock(0);
            // Check for ELSE
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .ELSE) {
                self.ip += 1;
                // Execute else block
                if (self.tokens.tokens[self.ip].ttype == .L_BRACE) {
                    self.ip += 1;
                }
            }
        }
    }

    fn handleWhile(self: *VM) void {
        const start_ip = self.ip;
        self.ip += 1; // skip while

        while (true) {
            if (keyboard.check_ctrl_c()) {
                common.printZ("\nInterrupted by Ctrl+C\n");
                self.exit_flag = true;
                return;
            }

            self.ip = start_ip + 1;
            const condition = self.evaluateExpression();

            if (condition.int_val != 0) {
                if (self.tokens.tokens[self.ip].ttype == .L_BRACE) {
                    self.ip += 1;
                }

                self.runBlock();

                if (self.break_flag) {
                    self.break_flag = false;
                    self.skipBlock(1);
                    break;
                }
                if (self.exit_flag) break;
                self.continue_flag = false;
                // Loop back
            } else {
                // Condition false, skip block and exit while
                self.skipBlock(0);
                break;
            }
        }
    }

    fn runBlock(self: *VM) void {
        if (self.tokens.tokens[self.ip].ttype == .L_BRACE) self.ip += 1;
        var depth: i32 = 1;
        while (self.ip < self.tokens.len and depth > 0 and !self.exit_flag and !self.break_flag and !self.continue_flag) {
            if (keyboard.check_ctrl_c()) {
                common.printZ("\nInterrupted by Ctrl+C\n");
                self.exit_flag = true;
                break;
            }
            const t = self.tokens.tokens[self.ip];
            if (t.ttype == .L_BRACE) depth += 1;
            if (t.ttype == .R_BRACE) {
                depth -= 1;
                if (depth == 0) {
                    self.ip += 1;
                    break;
                }
            }
            self.step();
        }
    }

    fn skipBlock(self: *VM, start_depth: i32) void {
        var depth: i32 = start_depth;
        while (self.ip < self.tokens.len) : (self.ip += 1) {
            const t = self.tokens.tokens[self.ip];
            if (t.ttype == .L_BRACE) depth += 1;
            if (t.ttype == .R_BRACE) {
                depth -= 1;
                if (depth == 0) {
                    self.ip += 1;
                    break;
                }
            }
        }
    }

    fn step(self: *VM) void {
        const t = self.tokens.tokens[self.ip];
        switch (t.ttype) {
            .DEF => self.handleDef(),
            .IMPORT => self.handleImport(),
            .IF => self.handleIf(),
            .WHILE => self.handleWhile(),
            .SET => self.handleSet(),
            .IDENTIFIER => self.handleAssignmentOrCall(),
            .BREAK => {
                self.break_flag = true;
                self.ip += 1;
            },
            .CONTINUE => {
                self.continue_flag = true;
                self.ip += 1;
            },
            .SEMICOLON => self.ip += 1,
            else => self.ip += 1,
        }
    }

    fn handleSet(self: *VM) void {
        self.ip += 1; // skip set
        if (self.ip >= self.tokens.len) return;

        const t = self.tokens.tokens[self.ip];
        if (t.ttype == .INT_TYPE or t.ttype == .STRING_TYPE) {
            self.ip += 1; // skip type
        }

        if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .IDENTIFIER) {
            self.handleAssignmentOrCall();
        } else {
            self.reportError("Expected identifier after set");
        }
    }

    fn handleAssignmentOrCall(self: *VM) void {
        const name = self.tokens.tokens[self.ip].value;
        self.ip += 1;

        if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .EQUALS) {
            self.ip += 1; // skip =
            const val = self.evaluateExpression();
            self.current_scope.table.put(name, val);
        } else if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .L_PAREN) {
            // Function call
            const result = self.handleCall(name);
            if (self.repl_mode and !common.streq(name, "print")) {
                if (result.vtype == .string) {
                    if (result.str_val.len > 0) {
                        common.printZ(result.str_val);
                        common.printZ("\n");
                    }
                } else if (result.vtype == .float) {
                    var buf: [32]u8 = undefined;
                    common.printZ(common.floatToString(result.float_val, &buf));
                    common.printZ("\n");
                } else {
                    var buf: [16]u8 = undefined;
                    common.printZ(common.intToString(result.int_val, &buf));
                    common.printZ("\n");
                }
            }
        } else {
            self.reportError("Expected '=' or '(' after identifier");
        }
    }

    fn handleCall(self: *VM, name: []const u8) hash_table.VariableValue {
        self.ip += 1; // skip (

        if (common.streq(name, "print")) {
            const val = self.evaluateExpression();
            if (val.vtype == .string) {
                common.printZ(val.str_val);
            } else if (val.vtype == .float) {
                var buf: [32]u8 = undefined;
                common.printZ(common.floatToString(val.float_val, &buf));
            } else {
                var buf: [16]u8 = undefined;
                common.printZ(common.intToString(val.int_val, &buf));
            }
            common.printZ("\n");
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            return .{ .vtype = .string, .str_val = "" };
        } else if (common.streq(name, "set_angles")) {
            const mode = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (mode.vtype == .string) {
                if (common.streq_ignore_case(mode.str_val, "rad")) {
                    self.angle_mode = .RAD;
                    return .{ .vtype = .string, .str_val = "Angle mode: RAD" };
                } else {
                    self.angle_mode = .DEG;
                    return .{ .vtype = .string, .str_val = "Angle mode: DEG" };
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Invalid mode" };
        } else if (common.streq(name, "rad")) {
            const val = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            const deg_v: f32 = if (val.vtype == .float) val.float_val else @floatFromInt(val.int_val);
            return .{ .vtype = .float, .float_val = deg_v * 3.14159 / 180.0 };
        } else if (common.streq(name, "deg")) {
            const val = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            const rad_v: f32 = if (val.vtype == .float) val.float_val else @floatFromInt(val.int_val);
            return .{ .vtype = .float, .float_val = rad_v * 180.0 / 3.14159 };
        } else if (common.streq(name, "random")) {
            const min_v = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const max_v = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            return .{ .vtype = .int, .int_val = global_common.get_random(min_v.int_val, max_v.int_val) };
        } else if (common.streq(name, "abs")) {
            const val = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (val.vtype == .int) {
                return .{ .vtype = .int, .int_val = if (val.int_val < 0) -val.int_val else val.int_val };
            }
            return val;
        } else if (common.streq(name, "min")) {
            const a = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const b = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (a.vtype == .int and b.vtype == .int) {
                return .{ .vtype = .int, .int_val = if (a.int_val < b.int_val) a.int_val else b.int_val };
            }
            return a;
        } else if (common.streq(name, "max")) {
            const a = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const b = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (a.vtype == .int and b.vtype == .int) {
                return .{ .vtype = .int, .int_val = if (a.int_val > b.int_val) a.int_val else b.int_val };
            }
            return a;
        } else if (common.streq(name, "sin")) {
            const val_v = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            var d: f32 = if (val_v.vtype == .float) val_v.float_val else @floatFromInt(val_v.int_val);
            if (self.angle_mode == .RAD) {
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
        } else if (common.streq(name, "cos")) {
            const val_v = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            var d: f32 = if (val_v.vtype == .float) val_v.float_val else @floatFromInt(val_v.int_val);
            if (self.angle_mode == .RAD) {
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
        } else if (common.streq(name, "create_file")) {
            const path = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (path.vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.write_file(drive, bpb, global_common.current_dir_cluster, path.str_val, "")) {
                        return .{ .vtype = .string, .str_val = "File created" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Could not create file" };
        } else if (common.streq(name, "delete") or common.streq(name, "remove") or common.streq(name, "rm")) {
            const path = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (path.vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.delete_file(drive, bpb, global_common.current_dir_cluster, path.str_val)) {
                        return .{ .vtype = .string, .str_val = "Removed" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Could not remove" };
        } else if (common.streq(name, "rename") or common.streq(name, "mv")) {
            const old_path = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const new_path = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (old_path.vtype == .string and new_path.vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.rename_file(drive, bpb, global_common.current_dir_cluster, old_path.str_val, new_path.str_val)) {
                        return .{ .vtype = .string, .str_val = "Renamed" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Could not rename" };
        } else if (common.streq(name, "copy") or common.streq(name, "cp")) {
            const src = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const dst = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (src.vtype == .string and dst.vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.copy_file(drive, bpb, global_common.current_dir_cluster, src.str_val, dst.str_val)) {
                        return .{ .vtype = .string, .str_val = "Copied" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Could not copy" };
        } else if (common.streq(name, "read")) {
            const path = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (path.vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    var buf_ptr = memory.heap.alloc(4096) orelse return .{ .vtype = .string, .str_val = "" };
                    const len = fat.read_file(drive, bpb, global_common.current_dir_cluster, path.str_val, buf_ptr);
                    if (len > 0) {
                        return .{ .vtype = .string, .str_val = buf_ptr[0..@intCast(len)] };
                    }
                    memory.heap.free(buf_ptr);
                }
            }
            return .{ .vtype = .string, .str_val = "" };
        } else if (common.streq(name, "write")) {
            const path = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const data = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;

            if (path.vtype == .string and data.vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.write_file(drive, bpb, global_common.current_dir_cluster, path.str_val, data.str_val)) {
                        return .{ .vtype = .string, .str_val = "Data written" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Write failed" };
        } else if (common.streq(name, "exists")) {
            const path = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            var res: i32 = 0;
            if (path.vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.resolve_full_path(drive, bpb, global_common.current_dir_cluster, global_common.current_path[0..global_common.current_path_len], path.str_val)) |_| {
                        res = 1;
                    }
                }
            }
            return .{ .vtype = .int, .int_val = res };
        } else if (common.streq(name, "mkdir")) {
            const path = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (path.vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.create_directory(drive, bpb, global_common.current_dir_cluster, path.str_val)) {
                        return .{ .vtype = .string, .str_val = "Directory created" };
                    }
                }
            }
            return .{ .vtype = .string, .str_val = "Error: Could not create directory" };
        } else if (common.streq(name, "size")) {
            const path = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            var res: i32 = -1;
            if (path.vtype == .string) {
                const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.find_entry(drive, bpb, global_common.current_dir_cluster, path.str_val)) |entry| {
                        res = @intCast(entry.file_size);
                    }
                }
            }
            return .{ .vtype = .int, .int_val = res };
        } else if (common.streq(name, "get_mem")) {
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            return .{ .vtype = .int, .int_val = @intCast(memory.get_free_memory()) };
        } else if (common.streq(name, "get_cpu_temp")) {
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            // Simple rdmsr for temperature (IA32_THERM_STATUS)
            var eax_val: u32 = 0;
            var edx_val: u32 = 0;
            const msr: u32 = 0x19C;
            asm volatile ("rdmsr"
                : [eax] "={eax}" (eax_val),
                  [edx] "={edx}" (edx_val),
                : [ecx] "{ecx}" (msr),
            );
            const readout = (eax_val >> 16) & 0x7F;
            // Note: This is usually (Tcc - readout). Default Tcc is ~100.
            return .{ .vtype = .int, .int_val = @intCast(100 - readout) };
        } else if (common.streq(name, "delay") or common.streq(name, "sleep")) {
            const val = self.evaluateExpression();
            if (val.vtype == .int) {
                global_common.sleep(@intCast(val.int_val));
            }
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            return .{ .vtype = .string, .str_val = "" };
        } else if (common.streq(name, "exec")) {
            const val = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (val.vtype == .string) {
                shell.shell_execute_literal(val.str_val);
            }
            return .{ .vtype = .string, .str_val = "" };
        } else if (common.streq(name, "len")) {
            const val = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (val.vtype == .string) return .{ .vtype = .int, .int_val = @intCast(val.str_val.len) };
            return .{ .vtype = .int, .int_val = 0 };
        } else if (common.streq(name, "int")) {
            const val = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (val.vtype == .string) return .{ .vtype = .int, .int_val = common.parseInt(val.str_val) };
            return val;
        } else if (common.streq(name, "str")) {
            const val = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (val.vtype == .int) {
                var buf_ptr = memory.heap.alloc(16) orelse return .{ .vtype = .string, .str_val = "0" };
                const s = common.intToString(val.int_val, buf_ptr[0..16]);
                return .{ .vtype = .string, .str_val = s };
            }
            return val;
        } else if (common.streq(name, "set_color")) {
            const fg = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const bg = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            vga.set_color(@intCast(fg.int_val), @intCast(bg.int_val));
            return .{ .vtype = .string, .str_val = "Colors updated" };
        } else if (common.streq(name, "get_key")) {
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            return .{ .vtype = .int, .int_val = @intCast(keyboard.keyboard_getchar()) };
        } else if (common.streq(name, "shell")) {
            const val = self.evaluateExpression();
            if (val.vtype == .string) {
                shell.shell_execute_literal(val.str_val);
            }
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            return .{ .vtype = .string, .str_val = "" };
        } else if (common.streq(name, "argc")) {
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            return .{ .vtype = .int, .int_val = @intCast(self.script_args.len) };
        } else if (common.streq(name, "args")) {
            const idx = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (idx.vtype == .int and idx.int_val >= 0 and idx.int_val < self.script_args.len) {
                return .{ .vtype = .string, .str_val = self.script_args[@intCast(idx.int_val)] };
            }
            return .{ .vtype = .string, .str_val = "" };
        } else if (common.streq(name, "input")) {
            const prompt = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (prompt.vtype == .string) common.printZ(prompt.str_val);

            var buf = memory.heap.alloc(128) orelse return .{ .vtype = .string, .str_val = "" };
            // Simple blocking read
            var len: usize = 0;
            while (len < 127) {
                const key = keyboard.keyboard_wait_char();
                if (key == 10 or key == 13) {
                    common.printZ("\n");
                    break;
                } else if (key == 8 or key == 127) {
                    if (len > 0) {
                        len -= 1;
                        common.printZ("\x08 \x08");
                    }
                } else if (key >= 32 and key <= 126) {
                    buf[len] = key;
                    len += 1;
                    common.print_char(key);
                }
            }
            return .{ .vtype = .string, .str_val = buf[0..len] };
        } else if (common.streq(name, "format_size")) {
            const bytes_v = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;
            if (bytes_v.vtype == .int) {
                const b = @as(u64, @intCast(bytes_v.int_val));
                const b_64 = b;
                const buf_ptr = memory.heap.alloc(32) orelse return .{ .vtype = .string, .str_val = "" };
                const buf = buf_ptr[0..32];
                var res: []const u8 = "";
                if (b_64 < 1024) {
                    res = common.intToString(@intCast(b_64), buf);
                    const final = buf[0 .. res.len + 2];
                    common.copy(buf[res.len..], " B");
                    return .{ .vtype = .string, .str_val = final };
                } else if (b_64 < 1024 * 1024) {
                    res = common.intToString(@intCast(b_64 / 1024), buf);
                    const final = buf[0 .. res.len + 3];
                    common.copy(buf[res.len..], " KB");
                    return .{ .vtype = .string, .str_val = final };
                } else if (b_64 < 1024 * 1024 * 1024) {
                    res = common.intToString(@intCast(b_64 / (1024 * 1024)), buf);
                    const final = buf[0 .. res.len + 3];
                    common.copy(buf[res.len..], " MB");
                    return .{ .vtype = .string, .str_val = final };
                } else {
                    res = common.intToString(@intCast(b_64 / (1024 * 1024 * 1024)), buf);
                    const final = buf[0 .. res.len + 3];
                    common.copy(buf[res.len..], " GB");
                    return .{ .vtype = .string, .str_val = final };
                }
            }
            return .{ .vtype = .string, .str_val = "0 B" };
        } else if (common.streq(name, "split")) {
            const str_v = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const sep_v = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const idx_v = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;

            if (str_v.vtype == .string and sep_v.vtype == .string and idx_v.vtype == .int) {
                const s = str_v.str_val;
                const sep = sep_v.str_val;
                const target_idx = idx_v.int_val;

                var current_idx: i32 = 0;
                var start: usize = 0;
                var i: usize = 0;
                while (i < s.len) {
                    if (common.startsWith(s[i..], sep)) {
                        if (current_idx == target_idx) {
                            return .{ .vtype = .string, .str_val = s[start..i] };
                        }
                        current_idx += 1;
                        i += sep.len;
                        start = i;
                    } else {
                        i += 1;
                    }
                }
                if (current_idx == target_idx) {
                    return .{ .vtype = .string, .str_val = s[start..] };
                }
            }
            return .{ .vtype = .string, .str_val = "" };
        } else if (common.streq(name, "format")) {
            const val = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const fmt = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;

            if (fmt.vtype == .string) {
                if (common.streq(fmt.str_val, "int")) {
                    if (val.vtype == .string) return .{ .vtype = .int, .int_val = common.parseInt(val.str_val) };
                    return val;
                } else if (common.streq(fmt.str_val, "str") or common.streq(fmt.str_val, "string")) {
                    if (val.vtype == .int) {
                        const buf_ptr = memory.heap.alloc(16) orelse return .{ .vtype = .string, .str_val = "0" };
                        const s = common.intToString(val.int_val, buf_ptr[0..16]);
                        return .{ .vtype = .string, .str_val = s };
                    }
                    return val;
                } else if (common.streq(fmt.str_val, "size")) {
                    // Reuse format_size logic
                    if (val.vtype == .int) {
                        const b_64 = @as(u64, @intCast(val.int_val));
                        const buf_ptr = memory.heap.alloc(32) orelse return .{ .vtype = .string, .str_val = "" };
                        const buf = buf_ptr[0..32];
                        var res_s: []const u8 = "";
                        if (b_64 < 1024) {
                            res_s = common.intToString(@intCast(b_64), buf);
                            const final = buf[0 .. res_s.len + 2];
                            common.copy(buf[res_s.len..], " B");
                            return .{ .vtype = .string, .str_val = final };
                        } else if (b_64 < 1024 * 1024) {
                            res_s = common.intToString(@intCast(b_64 / 1024), buf);
                            const final = buf[0 .. res_s.len + 3];
                            common.copy(buf[res_s.len..], " KB");
                            return .{ .vtype = .string, .str_val = final };
                        } else if (b_64 < 1024 * 1024 * 1024) {
                            res_s = common.intToString(@intCast(b_64 / (1024 * 1024)), buf);
                            const final = buf[0 .. res_s.len + 3];
                            common.copy(buf[res_s.len..], " MB");
                            return .{ .vtype = .string, .str_val = final };
                        } else {
                            res_s = common.intToString(@intCast(b_64 / (1024 * 1024 * 1024)), buf);
                            const final = buf[0 .. res_s.len + 3];
                            common.copy(buf[res_s.len..], " GB");
                            return .{ .vtype = .string, .str_val = final };
                        }
                    }
                } else if (common.streq(fmt.str_val, "hex")) {
                    if (val.vtype == .int) {
                        const buf_ptr = memory.heap.alloc(16) orelse return .{ .vtype = .string, .str_val = "0x0" };
                        const s = common.intToHex(@intCast(val.int_val), buf_ptr[0..16]);
                        return .{ .vtype = .string, .str_val = s };
                    }
                }
            }
            return val;
        } else if (common.streq(name, "convert")) {
            const val_v = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const from_v = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .COMMA) self.ip += 1;
            const to_v = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) self.ip += 1;

            if (val_v.vtype == .int and from_v.vtype == .string and to_v.vtype == .string) {
                var v = @as(u64, @intCast(val_v.int_val));
                const from = from_v.str_val;
                const to = to_v.str_val;

                // Normalize to bytes
                if (common.streq_ignore_case(from, "kb")) {
                    v *= 1024;
                } else if (common.streq_ignore_case(from, "mb")) {
                    v *= 1024 * 1024;
                } else if (common.streq_ignore_case(from, "gb")) {
                    v *= 1024 * 1024 * 1024;
                }

                // Convert to target
                if (common.streq_ignore_case(to, "kb")) {
                    v /= 1024;
                } else if (common.streq_ignore_case(to, "mb")) {
                    v /= 1024 * 1024;
                } else if (common.streq_ignore_case(to, "gb")) {
                    v /= 1024 * 1024 * 1024;
                }

                return .{ .vtype = .int, .int_val = @intCast(v) };
            }
            return val_v;
        } else if (common.streq(name, "exit")) {
            self.exit_flag = true;
            return .{ .vtype = .string, .str_val = "Goodbye!" };
        } else if (self.functions.get(name)) |func| {
            // Save state
            const old_ip = self.ip;
            const old_scope = self.current_scope;

            // Create new scope
            const scope_ptr = memory.heap.alloc(@sizeOf(Scope)) orelse return .{ .vtype = .int, .int_val = 0 };
            const new_scope: *Scope = @ptrCast(@alignCast(scope_ptr));
            new_scope.* = .{
                .table = hash_table.HashTable.init(8),
                .parent = old_scope,
            };
            self.current_scope = new_scope;

            // Jump to function
            self.ip = func.func_ptr;
            self.runBlock();

            // Restore state
            self.current_scope = old_scope;
            new_scope.table.deinit();
            memory.heap.free(@ptrCast(new_scope));
            self.ip = old_ip;

            // Skip call parens (we already handled ( above, but handleCall is called when ip is at ( )
            // Wait, if it's a user function, we need to skip the arguments if any.
            // For now, Nova doesn't support user function arguments well in this VM draft.
            while (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype != .R_PAREN) : (self.ip += 1) {}
            if (self.ip < self.tokens.len) self.ip += 1;

            return .{ .vtype = .int, .int_val = 0 };
        } else {
            // Skip call
            while (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype != .R_PAREN) : (self.ip += 1) {}
            if (self.ip < self.tokens.len) self.ip += 1;
            return .{ .vtype = .int, .int_val = 0 };
        }
    }

    fn handleImport(self: *VM) void {
        self.ip += 1; // skip import
        if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .STRING) {
            var raw_path = self.tokens.tokens[self.ip].value;
            if (raw_path.len >= 2) raw_path = raw_path[1 .. raw_path.len - 1];

            var path_buf: [128]u8 = undefined;
            const resolved_local = module.ModuleCache.resolvePath(self.current_file, raw_path, &path_buf);

            if (self.cache.isLoaded(resolved_local)) {
                self.ip += 1;
                return;
            }

            const resolved_ptr = memory.heap.alloc(resolved_local.len) orelse {
                self.reportError("Out of memory for path");
                return;
            };
            const resolved = resolved_ptr[0..resolved_local.len];
            common.copy(resolved, resolved_local);

            // Load and tokenize
            const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
            if (fat.read_bpb(drive)) |bpb| {
                // Try local dir, then system modules dir
                var found = false;
                var current_dir_cluster_val = global_common.current_dir_cluster;

                if (fat.find_entry(drive, bpb, current_dir_cluster_val, resolved)) |_| {
                    found = true;
                } else {
                    // Try /.SYSTEM/NOVA/MODULES/
                    if (fat.resolve_full_path(drive, bpb, 0, "/", ".SYSTEM/NOVA/MODULES")) |sys_mod_res| {
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

                        // Save current state
                        const old_tokens = self.tokens;
                        const old_ip = self.ip;
                        const old_file = self.current_file;

                        // Lex and Run sub-tokens
                        const new_tokens = lexer.tokenize(source);
                        self.tokens = new_tokens;
                        self.ip = 0;
                        self.current_file = resolved;
                        self.cache.markLoaded(resolved);

                        self.run();

                        // Restore state
                        self.tokens = old_tokens;
                        self.ip = old_ip;
                        self.current_file = old_file;
                    } else {
                        self.reportError("Could not read import file");
                    }
                } else {
                    self.reportError("Import file not found");
                }
            }
            self.ip += 1;
        } else {
            self.reportError("Expected string path for import");
        }
    }

    fn evaluateExpression(self: *VM) hash_table.VariableValue {
        return self.parseComparison();
    }

    fn parseComparison(self: *VM) hash_table.VariableValue {
        var left = self.parseTerm();

        while (self.ip < self.tokens.len) {
            const op = self.tokens.tokens[self.ip];
            if (op.ttype == .PLUS or op.ttype == .MINUS) {
                self.ip += 1;
                const right = self.parseTerm();
                if (left.vtype == .int and right.vtype == .int) {
                    if (op.ttype == .PLUS) left.int_val += right.int_val else left.int_val -= right.int_val;
                } else if ((left.vtype == .float or left.vtype == .int) and (right.vtype == .float or right.vtype == .int)) {
                    var lf: f32 = if (left.vtype == .float) left.float_val else @floatFromInt(left.int_val);
                    const rf: f32 = if (right.vtype == .float) right.float_val else @floatFromInt(right.int_val);
                    if (op.ttype == .PLUS) lf += rf else lf -= rf;
                    left = .{ .vtype = .float, .float_val = lf };
                } else if (left.vtype == .string and right.vtype == .string and op.ttype == .PLUS) {
                    const total_len = left.str_val.len + right.str_val.len;
                    const buf_ptr = memory.heap.alloc(total_len) orelse {
                        self.reportError("Out of memory for string concat");
                        return left;
                    };
                    const buf = buf_ptr[0..total_len];
                    common.copy(buf[0..left.str_val.len], left.str_val);
                    common.copy(buf[left.str_val.len..], right.str_val);
                    left = .{ .vtype = .string, .str_val = buf };
                } else if (left.vtype == .string and right.vtype == .int and op.ttype == .PLUS) {
                    var num_buf: [16]u8 = undefined;
                    const s_num = common.intToString(right.int_val, &num_buf);
                    const total_len = left.str_val.len + s_num.len;
                    const buf_ptr = memory.heap.alloc(total_len) orelse {
                        self.reportError("Out of memory for string concat");
                        return left;
                    };
                    const buf = buf_ptr[0..total_len];
                    common.copy(buf[0..left.str_val.len], left.str_val);
                    common.copy(buf[left.str_val.len..], s_num);
                    left = .{ .vtype = .string, .str_val = buf };
                } else if (left.vtype == .int and right.vtype == .string and op.ttype == .PLUS) {
                    var num_buf: [16]u8 = undefined;
                    const s_num = common.intToString(left.int_val, &num_buf);
                    const total_len = s_num.len + right.str_val.len;
                    const buf_ptr = memory.heap.alloc(total_len) orelse {
                        self.reportError("Out of memory for string concat");
                        return left;
                    };
                    const buf = buf_ptr[0..total_len];
                    common.copy(buf[0..s_num.len], s_num);
                    common.copy(buf[s_num.len..], right.str_val);
                    left = .{ .vtype = .string, .str_val = buf };
                }
            } else if (op.ttype == .EQUALS_EQUALS or op.ttype == .BANG_EQUALS or op.ttype == .LESS or op.ttype == .GREATER) {
                self.ip += 1;
                const right = self.parseTerm();
                var res = false;
                if (left.vtype == .int and right.vtype == .int) {
                    res = switch (op.ttype) {
                        .EQUALS_EQUALS => left.int_val == right.int_val,
                        .BANG_EQUALS => left.int_val != right.int_val,
                        .LESS => left.int_val < right.int_val,
                        .GREATER => left.int_val > right.int_val,
                        else => false,
                    };
                } else if ((left.vtype == .float or left.vtype == .int) and (right.vtype == .float or right.vtype == .int)) {
                    const lf: f32 = if (left.vtype == .float) left.float_val else @floatFromInt(left.int_val);
                    const rf: f32 = if (right.vtype == .float) right.float_val else @floatFromInt(right.int_val);
                    res = switch (op.ttype) {
                        .EQUALS_EQUALS => lf == rf,
                        .BANG_EQUALS => lf != rf,
                        .LESS => lf < rf,
                        .GREATER => lf > rf,
                        else => false,
                    };
                } else if (left.vtype == .string and right.vtype == .string) {
                    res = switch (op.ttype) {
                        .EQUALS_EQUALS => common.streq(left.str_val, right.str_val),
                        .BANG_EQUALS => !common.streq(left.str_val, right.str_val),
                        else => false,
                    };
                }
                left = .{ .vtype = .int, .int_val = if (res) 1 else 0 };
            } else {
                break;
            }
        }
        return left;
    }

    fn parseTerm(self: *VM) hash_table.VariableValue {
        var left = self.parseFactor();

        while (self.ip < self.tokens.len) {
            const op = self.tokens.tokens[self.ip];
            if (op.ttype == .STAR or op.ttype == .SLASH) {
                self.ip += 1;
                const right = self.parseFactor();
                if (left.vtype == .int and right.vtype == .int) {
                    if (op.ttype == .STAR) {
                        left.int_val *= right.int_val;
                    } else {
                        if (right.int_val != 0) left.int_val = @divTrunc(left.int_val, right.int_val) else left.int_val = 0;
                    }
                } else if ((left.vtype == .float or left.vtype == .int) and (right.vtype == .float or right.vtype == .int)) {
                    var lf: f32 = if (left.vtype == .float) left.float_val else @floatFromInt(left.int_val);
                    const rf: f32 = if (right.vtype == .float) right.float_val else @floatFromInt(right.int_val);
                    if (op.ttype == .STAR) {
                        lf *= rf;
                    } else {
                        if (rf != 0) lf /= rf else lf = 0;
                    }
                    left = .{ .vtype = .float, .float_val = lf };
                }
            } else {
                break;
            }
        }
        return left;
    }

    fn parseFactor(self: *VM) hash_table.VariableValue {
        if (self.ip >= self.tokens.len) return .{ .vtype = .int, .int_val = 0 };
        const t = self.tokens.tokens[self.ip];
        self.ip += 1;

        if (t.ttype == .NUMBER) {
            if (common.indexOf(t.value, '.') != null) {
                return .{ .vtype = .float, .float_val = common.parseFloat(t.value) };
            }
            return .{ .vtype = .int, .int_val = common.parseInt(t.value) };
        } else if (t.ttype == .STRING) {
            var val = t.value;
            if (val.len >= 2) val = val[1 .. val.len - 1];
            return .{ .vtype = .string, .str_val = val };
        } else if (t.ttype == .IDENTIFIER) {
            // Check for call
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .L_PAREN) {
                return self.handleCall(t.value);
            }

            // Lookup variable
            var s: ?*Scope = self.current_scope;
            while (s) |scope| {
                if (scope.table.get(t.value)) |v| return v;
                s = scope.parent;
            }
            if (self.globals.get(t.value)) |v| return v;
            return .{ .vtype = .int, .int_val = 0 };
        } else if (t.ttype == .L_PAREN) {
            const res = self.evaluateExpression();
            if (self.ip < self.tokens.len and self.tokens.tokens[self.ip].ttype == .R_PAREN) {
                self.ip += 1;
            }
            return res;
        } else if (t.ttype == .MINUS) {
            const val = self.parseFactor();
            if (val.vtype == .int) return .{ .vtype = .int, .int_val = -val.int_val };
            return val;
        }

        return .{ .vtype = .int, .int_val = 0 };
    }
};
