const common = @import("common.zig");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const hash_table = @import("hash_table.zig");
const arena_mod = @import("arena.zig");

const TokenType = lexer.TokenType;

pub const Parser = struct {
    tokens: lexer.TokenList,
    ip: usize,
    arena: *arena_mod.Arena,
    had_error: bool,
    panic_mode: bool,

    pub fn init(tokens: lexer.TokenList, arena: *arena_mod.Arena) Parser {
        return .{
            .tokens = tokens,
            .ip = 0,
            .arena = arena,
            .had_error = false,
            .panic_mode = false,
        };
    }

    pub fn parseProgram(self: *Parser) ?*ast.Node {
        const prog = self.arena.alloc(ast.Node);
        prog.* = .{ .node_type = .program, .line = 0 };

        var stmts: [256]*ast.Node = undefined;
        var count: usize = 0;

        while (self.peek().ttype != .EOF) {
            const stmt = self.parseStatement();
            if (stmt) |s| {
                stmts[count] = s;
                count += 1;
            } else {
                if (self.peek().ttype == .EOF) break;
                self.synchronize();
            }
        }

        const stmts_ptr = self.arena.allocBytes(count * @sizeOf(*ast.Node));
        const ptr: [*]*ast.Node = @ptrCast(@alignCast(stmts_ptr.ptr));
        for (0..count) |i| ptr[i] = stmts[i];

        prog.stmts = ptr;
        prog.stmt_count = count;
        return prog;
    }

    fn parseStatement(self: *Parser) ?*ast.Node {
        if (self.panic_mode) return null;

        const tt = self.peek().ttype;
        switch (tt) {
            .INT_TYPE, .FLOAT_TYPE, .STRING_TYPE => return self.parseVarDecl(),
            .IF => return self.parseIf(),
            .WHILE => return self.parseWhile(),
            .FOR => return self.parseFor(),
            .DEF => return self.parseFunctionDef(),
            .RETURN => return self.parseReturn(),
            .IMPORT => return self.parseImport(),
            .BREAK => {
                const node = self.arena.alloc(ast.Node);
                node.* = .{ .node_type = .break_stmt, .line = self.peek().line };
                self.ip += 1;
                self.expect(.SEMICOLON);
                return node;
            },
            .CONTINUE => {
                const node = self.arena.alloc(ast.Node);
                node.* = .{ .node_type = .continue_stmt, .line = self.peek().line };
                self.ip += 1;
                self.expect(.SEMICOLON);
                return node;
            },
            .L_BRACE => return self.parseBlock(),
            .SEMICOLON => {
                self.ip += 1;
                return null;
            },
            .EOF => return null,
            .UNKNOWN => {
                self.parseError("Unexpected token");
                self.ip += 1;
                return null;
            },
            else => return self.parseExpressionStatement(),
        }
    }

    fn parseVarDecl(self: *Parser) ?*ast.Node {
        const type_token = self.consume();
        const decl_type: ?hash_table.VariableType = switch (type_token.ttype) {
            .INT_TYPE => .int,
            .FLOAT_TYPE => .float,
            .STRING_TYPE => .string,
            else => unreachable,
        };

        if (self.peek().ttype != .IDENTIFIER) {
            self.parseError("Expected variable name after type");
            return null;
        }
        const name_token = self.consume();
        const name = self.copyStr(name_token.value);

        var init_node: ?*ast.Node = null;
        if (self.peek().ttype == .EQUALS) {
            self.ip += 1;
            init_node = self.parseExpression();
        }

        self.expect(.SEMICOLON);

        const node = self.arena.alloc(ast.Node);
        node.* = .{
            .node_type = .var_decl,
            .line = type_token.line,
            .str_val = name,
            .decl_type = decl_type,
            .left = init_node,
        };
        return node;
    }

    fn parseIf(self: *Parser) ?*ast.Node {
        const if_token = self.consume();
        self.expect(.L_PAREN);
        const cond = self.parseExpression();
        self.expect(.R_PAREN);
        const then_block = self.parseBlock();

    var else_block: ?*ast.Node = null;
    if (self.peek().ttype == .ELSE) {
        self.ip += 1;
        else_block = self.parseBlock();
    }

    const node = self.arena.alloc(ast.Node);
    node.* = .{
        .node_type = .if_stmt,
        .line = if_token.line,
        .left = cond,
        .right = then_block,
        .stmt_count = 0,
    };
    if (else_block) |eb| {
        const mem = self.arena.allocBytes(@sizeOf(*ast.Node));
        const ptr: [*]*ast.Node = @ptrCast(@alignCast(mem.ptr));
        ptr[0] = eb;
        node.stmts = ptr;
        node.stmt_count = 1;
    }
    return node;
    }

    fn parseWhile(self: *Parser) ?*ast.Node {
        const while_token = self.consume();
        self.expect(.L_PAREN);
        const cond = self.parseExpression();
        self.expect(.R_PAREN);
        const body = self.parseBlock();

        const node = self.arena.alloc(ast.Node);
        node.* = .{
            .node_type = .while_stmt,
            .line = while_token.line,
            .left = cond,
            .right = body,
        };
        return node;
    }

    fn parseFor(self: *Parser) ?*ast.Node {
        const for_token = self.consume();
        self.expect(.L_PAREN);

        var init_node: ?*ast.Node = null;
        if (self.peek().ttype != .SEMICOLON) {
            if (self.peek().ttype == .INT_TYPE or self.peek().ttype == .FLOAT_TYPE or self.peek().ttype == .STRING_TYPE) {
                init_node = self.parseVarDecl();
            } else {
                init_node = self.parseExpressionStatement();
            }
        } else {
            self.ip += 1;
        }

        var cond_node: ?*ast.Node = null;
        if (self.peek().ttype != .SEMICOLON) {
            cond_node = self.parseExpression();
        }
        self.expect(.SEMICOLON);

        var inc_node: ?*ast.Node = null;
        if (self.peek().ttype != .R_PAREN) {
            inc_node = self.parseExpressionStatement();
        }
        self.expect(.R_PAREN);

        const body = self.parseBlock();

        const node = self.arena.alloc(ast.Node);
        node.* = .{
            .node_type = .for_stmt,
            .line = for_token.line,
            .str_val = "",
        };
        // Store init/cond/inc/body using left/right + stmts
        // left = cond, right = body, stmts[0] = init, stmts[1] = inc
        node.left = cond_node;
        node.right = body;
        var ptr: [*]*ast.Node = undefined;
        const mem = self.arena.allocBytes(2 * @sizeOf(*ast.Node));
        ptr = @ptrCast(@alignCast(mem.ptr));
        ptr[0] = if (init_node) |n| n else @as(*ast.Node, undefined);
        ptr[1] = if (inc_node) |n| n else @as(*ast.Node, undefined);
        node.stmts = ptr;
        node.stmt_count = 2;
        return node;
    }

    fn parseFunctionDef(self: *Parser) ?*ast.Node {
        const def_token = self.consume();

        if (self.peek().ttype != .IDENTIFIER) {
            self.parseError("Expected function name");
            return null;
        }
        const name_token = self.consume();
        const name = self.copyStr(name_token.value);

        self.expect(.L_PAREN);

        var param_names: [8][]const u8 = undefined;
        var param_count: usize = 0;
        if (self.peek().ttype != .R_PAREN) {
            while (true) {
                if (self.peek().ttype != .IDENTIFIER) {
                    self.parseError("Expected parameter name");
                    break;
                }
                const p = self.consume();
                param_names[param_count] = self.copyStr(p.value);
                param_count += 1;
                if (self.peek().ttype == .COMMA) {
                    self.ip += 1;
                } else {
                    break;
                }
            }
        }
        self.expect(.R_PAREN);

        const body = self.parseBlock();

        // Store param names in stmts array
        const params_ptr = self.arena.allocBytes(param_count * @sizeOf(*ast.Node));
        const ptr: [*]*ast.Node = @ptrCast(@alignCast(params_ptr.ptr));
        for (0..param_count) |i| {
            const pnode = self.arena.alloc(ast.Node);
            pnode.* = .{ .node_type = .ident, .line = def_token.line, .str_val = param_names[i] };
            ptr[i] = pnode;
        }

        const node = self.arena.alloc(ast.Node);
        node.* = .{
            .node_type = .func_def,
            .line = def_token.line,
            .str_val = name,
            .right = body,
            .stmts = ptr,
            .stmt_count = param_count,
        };
        return node;
    }

    fn parseReturn(self: *Parser) ?*ast.Node {
        const ret_token = self.consume();
        var expr: ?*ast.Node = null;
        if (self.peek().ttype != .SEMICOLON) {
            expr = self.parseExpression();
        }
        self.expect(.SEMICOLON);

        const node = self.arena.alloc(ast.Node);
        node.* = .{
            .node_type = .return_stmt,
            .line = ret_token.line,
            .left = expr,
        };
        return node;
    }

    fn parseBlock(self: *Parser) ?*ast.Node {
        if (self.peek().ttype != .L_BRACE) {
            self.parseError("Expected '{'");
            return null;
        }
        const brace_token = self.consume();

        var stmts: [256]*ast.Node = undefined;
        var count: usize = 0;

        while (self.peek().ttype != .R_BRACE and self.peek().ttype != .EOF) {
            const stmt = self.parseStatement();
            if (stmt) |s| {
                stmts[count] = s;
                count += 1;
            } else {
                if (self.peek().ttype == .R_BRACE or self.peek().ttype == .EOF) break;
                self.synchronize();
            }
        }

        if (self.peek().ttype == .R_BRACE) {
            self.ip += 1;
        } else {
            self.parseError("Expected '}'");
        }

        const node = self.arena.alloc(ast.Node);
        node.* = .{ .node_type = .block, .line = brace_token.line, .stmt_count = count };

        if (count > 0) {
            const mem = self.arena.allocBytes(count * @sizeOf(*ast.Node));
            const ptr: [*]*ast.Node = @ptrCast(@alignCast(mem.ptr));
            for (0..count) |i| ptr[i] = stmts[i];
            node.stmts = ptr;
        }

        return node;
    }

    fn parseImport(self: *Parser) ?*ast.Node {
        const import_token = self.consume();
        if (self.peek().ttype != .STRING) {
            self.parseError("Expected string path for import");
            return null;
        }
        const path_token = self.consume();
        var path = path_token.value;
        if (path.len >= 2) path = path[1 .. path.len - 1];
        self.expect(.SEMICOLON);

        const node = self.arena.alloc(ast.Node);
        node.* = .{
            .node_type = .import_stmt,
            .line = import_token.line,
            .str_val = self.copyStr(path),
        };
        return node;
    }

    fn parseExpressionStatement(self: *Parser) ?*ast.Node {
        const node = self.parseExpression();
        self.expect(.SEMICOLON);
        return node;
    }

    fn parseExpression(self: *Parser) ?*ast.Node {
        return self.parseAssignment();
    }

    fn parseAssignment(self: *Parser) ?*ast.Node {
        const node = self.parseEquality();
        if (node == null) return null;

        if (self.peek().ttype == .EQUALS) {
            if (node.?.node_type != .ident) {
                self.parseError("Left side of assignment must be a variable");
                return node;
            }
            self.ip += 1;
            const val = self.parseAssignment();
            if (val == null) return node;

            const assign = self.arena.alloc(ast.Node);
            assign.* = .{
                .node_type = .assign,
                .line = node.?.line,
                .str_val = node.?.str_val,
                .left = val,
            };
            return assign;
        }
        return node;
    }

    fn parseEquality(self: *Parser) ?*ast.Node {
        var node = self.parseComparison();
        if (node == null) return null;

        while (self.peek().ttype == .EQUALS_EQUALS or self.peek().ttype == .BANG_EQUALS) {
            const op_token = self.consume();
            const op: ast.BinOp = if (op_token.ttype == .EQUALS_EQUALS) .eq else .neq;
            const right = self.parseComparison();
            if (right == null) return node;

            const bin = self.arena.alloc(ast.Node);
            bin.* = .{
                .node_type = .bin_op,
                .line = op_token.line,
                .bin_op = op,
                .left = node,
                .right = right,
            };
            node = bin;
        }
        return node;
    }

    fn parseComparison(self: *Parser) ?*ast.Node {
        var node = self.parseTerm();
        if (node == null) return null;

        while (true) {
            const tt = self.peek().ttype;
            const op: ?ast.BinOp = switch (tt) {
                .LESS => .lt,
                .GREATER => .gt,
                else => null,
            };
            if (op) |o| {
                self.ip += 1;
                const right = self.parseTerm();
                if (right == null) return node;

                const bin = self.arena.alloc(ast.Node);
                bin.* = .{
                    .node_type = .bin_op,
                    .line = self.tokens.tokens[self.ip - 1].line,
                    .bin_op = o,
                    .left = node,
                    .right = right,
                };
                node = bin;
            } else {
                break;
            }
        }
        return node;
    }

    fn parseTerm(self: *Parser) ?*ast.Node {
        var node = self.parseFactor();
        if (node == null) return null;

        while (true) {
            const tt = self.peek().ttype;
            const op: ?ast.BinOp = switch (tt) {
                .PLUS => .add,
                .MINUS => .sub,
                else => null,
            };
            if (op) |o| {
                self.ip += 1;
                const right = self.parseFactor();
                if (right == null) return node;

                const bin = self.arena.alloc(ast.Node);
                bin.* = .{
                    .node_type = .bin_op,
                    .line = self.tokens.tokens[self.ip - 1].line,
                    .bin_op = o,
                    .left = node,
                    .right = right,
                };
                node = bin;
            } else {
                break;
            }
        }
        return node;
    }

    fn parseFactor(self: *Parser) ?*ast.Node {
        var node = self.parseUnary();
        if (node == null) return null;

        while (true) {
            const tt = self.peek().ttype;
            const op: ?ast.BinOp = switch (tt) {
                .STAR => .mul,
                .SLASH => .div,
                .PERCENT => .mod,
                else => null,
            };
            if (op) |o| {
                self.ip += 1;
                const right = self.parseUnary();
                if (right == null) return node;

                const bin = self.arena.alloc(ast.Node);
                bin.* = .{
                    .node_type = .bin_op,
                    .line = self.tokens.tokens[self.ip - 1].line,
                    .bin_op = o,
                    .left = node,
                    .right = right,
                };
                node = bin;
            } else {
                break;
            }
        }
        return node;
    }

    fn parseUnary(self: *Parser) ?*ast.Node {
        const tt = self.peek().ttype;
        if (tt == .MINUS) {
            const tok = self.consume();
            const operand = self.parseUnary();
            if (operand == null) return null;
            const node = self.arena.alloc(ast.Node);
            node.* = .{
                .node_type = .unary_op,
                .line = tok.line,
                .unary_op = .neg,
                .left = operand,
            };
            return node;
        }
        if (tt == .TILDE) {
            const tok = self.consume();
            const operand = self.parseUnary();
            if (operand == null) return null;
            const node = self.arena.alloc(ast.Node);
            node.* = .{
                .node_type = .unary_op,
                .line = tok.line,
                .unary_op = .bit_not,
                .left = operand,
            };
            return node;
        }
        return self.parseCall();
    }

    fn parseCall(self: *Parser) ?*ast.Node {
        const node = self.parsePrimary();
        if (node == null) return null;

        if (self.peek().ttype == .L_PAREN) {
            self.ip += 1;

            var args: [8]*ast.Node = undefined;
            var arg_count: usize = 0;

            if (self.peek().ttype != .R_PAREN) {
                while (true) {
                    const arg = self.parseExpression();
                    if (arg) |a| {
                        args[arg_count] = a;
                        arg_count += 1;
                    }
                    if (self.peek().ttype == .COMMA) {
                        self.ip += 1;
                    } else {
                        break;
                    }
                }
            }

            if (self.peek().ttype == .R_PAREN) {
                self.ip += 1;
            } else {
                self.parseError("Expected ')' after arguments");
            }

            // Build func_call node
            const func_name = self.arena.alloc(ast.Node);
            func_name.* = .{ .node_type = .ident, .line = node.?.line, .str_val = node.?.str_val };

            const call = self.arena.alloc(ast.Node);
            call.* = .{
                .node_type = .func_call,
                .line = node.?.line,
                .str_val = node.?.str_val,
                .stmt_count = arg_count,
            };

            if (arg_count > 0) {
                const mem = self.arena.allocBytes(arg_count * @sizeOf(*ast.Node));
                const ptr: [*]*ast.Node = @ptrCast(@alignCast(mem.ptr));
                for (0..arg_count) |i| ptr[i] = args[i];
                call.stmts = ptr;
            }
            return call;
        }

        // Handle namespace access: math.sin → func_call with name "math.sin"
        if (self.peek().ttype == .DOT) {
            self.ip += 1;
            if (self.peek().ttype == .IDENTIFIER) {
                const member = self.consume();
                const combined = self.copyConcat(node.?.str_val, ".", member.value);

                // Check if it's a call: math.sin(x)
                if (self.peek().ttype == .L_PAREN) {
                    self.ip += 1;
                    var args: [8]*ast.Node = undefined;
                    var arg_count: usize = 0;

                    if (self.peek().ttype != .R_PAREN) {
                        while (true) {
                            const arg = self.parseExpression();
                            if (arg) |a| {
                                args[arg_count] = a;
                                arg_count += 1;
                            }
                            if (self.peek().ttype == .COMMA) {
                                self.ip += 1;
                            } else {
                                break;
                            }
                        }
                    }

                    if (self.peek().ttype == .R_PAREN) {
                        self.ip += 1;
                    } else {
                        self.parseError("Expected ')' after arguments");
                    }

                    const call = self.arena.alloc(ast.Node);
                    call.* = .{
                        .node_type = .func_call,
                        .line = node.?.line,
                        .str_val = combined,
                        .stmt_count = arg_count,
                    };

                    if (arg_count > 0) {
                        const mem = self.arena.allocBytes(arg_count * @sizeOf(*ast.Node));
                        const ptr: [*]*ast.Node = @ptrCast(@alignCast(mem.ptr));
                        for (0..arg_count) |i| ptr[i] = args[i];
                        call.stmts = ptr;
                    }
                    return call;
                }

                // Just a namespace path (rare standalone)
                const ident = self.arena.alloc(ast.Node);
                ident.* = .{ .node_type = .ident, .line = node.?.line, .str_val = combined };
                return ident;
            }
        }

        return node;
    }

    fn parsePrimary(self: *Parser) ?*ast.Node {
        const tt = self.peek().ttype;
        const tok = self.consume();

        switch (tt) {
            .NUMBER => {
                if (common.indexOf(tok.value, '.') != null) {
                    const node = self.arena.alloc(ast.Node);
                    node.* = .{
                        .node_type = .float_lit,
                        .line = tok.line,
                        .float_val = common.parseFloat(tok.value),
                    };
                    return node;
                }
                const node = self.arena.alloc(ast.Node);
                node.* = .{
                    .node_type = .int_lit,
                    .line = tok.line,
                    .int_val = common.parseInt(tok.value),
                };
                return node;
            },
            .STRING => {
                var val = tok.value;
                if (val.len >= 2) val = val[1 .. val.len - 1];
                const node = self.arena.alloc(ast.Node);
                node.* = .{
                    .node_type = .str_lit,
                    .line = tok.line,
                    .str_val = self.copyStr(val),
                };
                return node;
            },
            .IDENTIFIER => {
                const node = self.arena.alloc(ast.Node);
                node.* = .{
                    .node_type = .ident,
                    .line = tok.line,
                    .str_val = self.copyStr(tok.value),
                };
                return node;
            },
            .L_PAREN => {
                const node = self.parseExpression();
                if (self.peek().ttype == .R_PAREN) {
                    self.ip += 1;
                } else {
                    self.parseError("Expected ')' after expression");
                }
                return node;
            },
            else => {
                self.parseError("Unexpected token in expression");
                return null;
            },
        }
    }

    fn peek(self: *Parser) lexer.Token {
        if (self.ip < self.tokens.len) return self.tokens.tokens[self.ip];
        return .{ .ttype = .EOF, .value = "", .line = 0 };
    }

    fn consume(self: *Parser) lexer.Token {
        const t = self.peek();
        self.ip += 1;
        return t;
    }

    fn expect(self: *Parser, expected: TokenType) void {
        if (self.peek().ttype == expected) {
            self.ip += 1;
        } else {
            self.parseError("Expected token");
        }
    }

    fn copyStr(self: *Parser, s: []const u8) []const u8 {
        if (s.len == 0) return "";
        const copy = self.arena.allocBytes(s.len);
        @memcpy(copy, s);
        return copy;
    }

    fn copyConcat(self: *Parser, a: []const u8, sep: []const u8, b: []const u8) []const u8 {
        const total = a.len + sep.len + b.len;
        const copy = self.arena.allocBytes(total);
        @memcpy(copy[0..a.len], a);
        @memcpy(copy[a.len..][0..sep.len], sep);
        @memcpy(copy[a.len + sep.len ..], b);
        return copy;
    }

    fn parseError(self: *Parser, msg: []const u8) void {
        if (self.panic_mode) return;
        self.had_error = true;
        self.panic_mode = true;
        const line = self.peek().line;
        common.printZ("Parse error at line ");
        var buf: [16]u8 = undefined;
        common.printZ(common.intToString(@intCast(line), &buf));
        common.printZ(": ");
        common.printZ(msg);
        common.printZ("\n");
    }

    fn synchronize(self: *Parser) void {
        self.panic_mode = false;
        while (self.ip < self.tokens.len) {
            const tt = self.tokens.tokens[self.ip].ttype;
            if (tt == .SEMICOLON or tt == .R_BRACE or tt == .EOF) {
                if (tt == .SEMICOLON) self.ip += 1;
                return;
            }
            switch (tt) {
                .INT_TYPE, .FLOAT_TYPE, .STRING_TYPE, .IF, .WHILE, .FOR, .DEF, .RETURN, .BREAK, .CONTINUE => return,
                else => self.ip += 1,
            }
        }
    }
};
