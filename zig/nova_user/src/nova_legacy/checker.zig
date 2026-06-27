const common = @import("common.zig");
const ast = @import("ast.zig");
const hash_table = @import("hash_table.zig");
const user = @import("../user.zig");

const Node = ast.Node;
const VariableType = hash_table.VariableType;

const Scope = struct {
    table: hash_table.HashTable,
    parent: ?*Scope,
};

pub const Checker = struct {
    scope: ?*Scope,
    had_error: bool,
    in_loop: bool,

    pub fn init() Checker {
        return .{
            .scope = null,
            .had_error = false,
            .in_loop = false,
        };
    }

    pub fn check(self: *Checker, node: *Node) void {
        switch (node.node_type) {
            .program => self.checkProgram(node),
            .block => self.checkBlock(node),
            .var_decl => self.checkVarDecl(node),
            .assign => self.checkAssign(node),
            .func_call => self.checkFuncCall(node),
            .bin_op => self.checkBinOp(node),
            .unary_op => self.checkUnaryOp(node),
            .if_stmt => self.checkIf(node),
            .while_stmt => self.checkWhile(node),
            .for_stmt => self.checkFor(node),
            .func_def => {},
            .import_stmt => {},
            .return_stmt => {
                if (node.left) |expr| self.check(expr);
                node.resolved_type = if (node.left) |l| l.resolved_type else .int;
            },
            .break_stmt, .continue_stmt => {
                if (!self.in_loop) {
                    self.errorAt(node, "break/continue outside loop");
                }
            },
            .int_lit => node.resolved_type = .int,
            .float_lit => node.resolved_type = .float,
            .str_lit => node.resolved_type = .string,
            .ident => self.checkIdent(node),
        }
    }

    fn pushScope(self: *Checker) void {
        const ptr = user.user_malloc(@sizeOf(Scope)) orelse return;
        const scope: *Scope = @ptrCast(@alignCast(ptr));
        scope.* = .{
            .table = hash_table.HashTable.init(8),
            .parent = self.scope,
        };
        self.scope = scope;
    }

    fn popScope(self: *Checker) void {
        if (self.scope) |s| {
            self.scope = s.parent;
            s.table.deinit();
            user.user_free(@ptrCast(s));
        }
    }

    fn declareVar(self: *Checker, name: []const u8, vtype: VariableType) void {
        if (self.scope) |s| {
            s.table.put(name, .{ .vtype = vtype, .int_val = 0 });
        }
    }

    fn lookupVar(self: *Checker, name: []const u8) ?VariableType {
        var s = self.scope;
        while (s) |scope| {
            if (scope.table.get(name)) |v| return v.vtype;
            s = scope.parent;
        }
        return null;
    }

    fn checkProgram(self: *Checker, node: *Node) void {
        self.pushScope();
        var i: usize = 0;
        while (i < node.stmt_count) : (i += 1) {
            self.check(node.stmts.?[i]);
        }
    }

    fn checkBlock(self: *Checker, node: *Node) void {
        self.pushScope();
        var i: usize = 0;
        while (i < node.stmt_count) : (i += 1) {
            self.check(node.stmts.?[i]);
        }
        self.popScope();
    }

    fn checkVarDecl(self: *Checker, node: *Node) void {
        const declared = node.decl_type orelse {
            self.errorAt(node, "Variable declaration missing type");
            return;
        };
        if (node.left) |initial| {
            self.check(initial);
            if (initial.resolved_type) |init_type| {
                if (init_type != declared) {
                    if (!(init_type == .int and declared == .float)) {
                        self.errorAt(node, "Type mismatch in variable declaration");
                        return;
                    }
                }
            }
        }
        self.declareVar(node.str_val, declared);
        node.resolved_type = declared;
    }

    fn checkAssign(self: *Checker, node: *Node) void {
        const existing = self.lookupVar(node.str_val);
        if (existing == null) {
            self.errorAt(node, "Undefined variable");
            node.resolved_type = .int;
            return;
        }
        if (node.left) |val| {
            self.check(val);
            if (val.resolved_type) |val_type| {
                if (val_type != existing.? and !(val_type == .int and existing.? == .float)) {
                    self.errorAt(node, "Type mismatch in assignment");
                }
            }
        }
        node.resolved_type = existing;
    }

    fn checkFuncCall(self: *Checker, node: *Node) void {
        var i: usize = 0;
        while (i < node.stmt_count) : (i += 1) {
            self.check(node.stmts.?[i]);
        }
        const name = node.str_val;
        if (common.streq(name, "print") or common.streq(name, "exit") or
            common.streq(name, "sys.color") or common.streq(name, "sys.cls") or
            common.streq(name, "sys.delay") or common.streq(name, "sys.sleep") or
            common.streq(name, "sys.exec") or common.streq(name, "sys.shell") or
            common.streq(name, "create_file") or common.streq(name, "mkdir") or
            common.streq(name, "write") or common.streq(name, "delete") or
            common.streq(name, "remove") or common.streq(name, "rm") or
            common.streq(name, "rename") or common.streq(name, "mv") or
            common.streq(name, "copy") or common.streq(name, "cp") or
            common.streq(name, "speaker.beep") or
            common.streq(name, "sys.whoami") or common.streq(name, "sys.uname"))
        {
            node.resolved_type = .string;
        } else if (common.streq(name, "len") or common.streq(name, "int") or
            common.streq(name, "argc") or common.streq(name, "exists") or
            common.streq(name, "size") or common.streq(name, "sys.key") or
            common.streq(name, "sys.get_mem") or common.streq(name, "sys.get_temp") or
            common.streq(name, "sys.uptime") or common.streq(name, "sys.get_res_x") or
            common.streq(name, "sys.get_res_y") or
            common.streq(name, "math.floor") or common.streq(name, "math.ceil") or
            common.streq(name, "math.round"))
        {
            node.resolved_type = .int;
        } else if (common.streq(name, "str") or common.streq(name, "format") or
            common.streq(name, "input") or common.streq(name, "read") or
            common.streq(name, "format_size") or common.streq(name, "split") or
            common.streq(name, "convert") or common.streq(name, "args"))
        {
            node.resolved_type = .string;
        } else if (common.startsWith(name, "math.")) {
            node.resolved_type = .float;
        } else {
            node.resolved_type = .int;
        }
    }

    fn checkBinOp(self: *Checker, node: *Node) void {
        if (node.left) |l| self.check(l);
        if (node.right) |r| self.check(r);

        const lt = if (node.left) |l| l.resolved_type else null;
        const rt = if (node.right) |r| r.resolved_type else null;

        if (lt == null or rt == null) {
            node.resolved_type = .int;
            return;
        }

        const op = node.bin_op;

        if (op == .add or op == .sub or op == .mul or op == .div or op == .mod) {
            if (lt.? == .string and rt.? == .string and op == .add) {
                node.resolved_type = .string;
                return;
            }
            if (lt.? == .string or rt.? == .string) {
                self.errorAt(node, "Cannot use string in arithmetic (use str())");
                node.resolved_type = .int;
                return;
            }
            node.resolved_type = if (lt.? == .float or rt.? == .float) .float else .int;
            return;
        }

        if (op == .eq or op == .neq or op == .lt or op == .gt) {
            if (lt.? != rt.? and !(lt.? == .int and rt.? == .float) and !(lt.? == .float and rt.? == .int)) {
                self.errorAt(node, "Type mismatch in comparison");
            }
            node.resolved_type = .int;
            return;
        }

        node.resolved_type = .int;
    }

    fn checkUnaryOp(self: *Checker, node: *Node) void {
        if (node.left) |op| self.check(op);
        node.resolved_type = if (node.left) |l| l.resolved_type else .int;
    }

    fn checkIf(self: *Checker, node: *Node) void {
        if (node.left) |cond| {
            self.check(cond);
            if (cond.resolved_type != null and cond.resolved_type.? != .int) {
                self.errorAt(node, "If condition must be int");
            }
        }
        if (node.right) |then_block| self.check(then_block);
        if (node.stmt_count > 0 and node.stmts != null) {
            self.check(node.stmts.?[0]);
        }
    }

    fn checkWhile(self: *Checker, node: *Node) void {
        if (node.left) |cond| {
            self.check(cond);
            if (cond.resolved_type != null and cond.resolved_type.? != .int) {
                self.errorAt(node, "While condition must be int");
            }
        }
        const prev = self.in_loop;
        self.in_loop = true;
        if (node.right) |body| self.check(body);
        self.in_loop = prev;
    }

    fn checkFor(self: *Checker, node: *Node) void {
        self.pushScope();
        if (node.stmt_count >= 1 and node.stmts != null) {
            const initial = node.stmts.?[0];
            self.check(initial);
        }
        if (node.left) |cond| {
            self.check(cond);
            if (cond.resolved_type != null and cond.resolved_type.? != .int) {
                self.errorAt(node, "For condition must be int");
            }
        }
        if (node.stmt_count >= 2 and node.stmts != null) {
            const inc = node.stmts.?[1];
            self.check(inc);
        }
        const prev = self.in_loop;
        self.in_loop = true;
        if (node.right) |body| self.check(body);
        self.in_loop = prev;
        self.popScope();
    }

    fn checkIdent(self: *Checker, node: *Node) void {
        if (self.lookupVar(node.str_val)) |vt| {
            node.resolved_type = vt;
        } else {
            self.errorAt(node, "Undefined variable");
            node.resolved_type = .int;
        }
    }

    fn errorAt(self: *Checker, node: *Node, msg: []const u8) void {
        self.had_error = true;
        common.printZ("Type error at line ");
        var buf: [16]u8 = undefined;
        common.printZ(common.intToString(@intCast(node.line), &buf));
        common.printZ(": ");
        common.printZ(msg);
        common.printZ("\n");
    }
};
