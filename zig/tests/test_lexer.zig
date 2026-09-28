const std = @import("std");

// Ported lexer logic for host testing (avoids user_malloc dependency)

var test_allocator = std.heap.page_allocator;

pub const TokenType = enum {
    DEF, IMPORT, IDENTIFIER, NUMBER, STRING, EQUALS,
    IF, WHILE, ELSE, SET, INT_TYPE, STRING_TYPE,
    L_BRACE, R_BRACE, L_PAREN, R_PAREN, COMMA, SEMICOLON,
    PLUS, MINUS, STAR, SLASH, BANG_EQUALS, EQUALS_EQUALS,
    LESS, GREATER, BREAK, CONTINUE, DOT, AMPERSAND, PIPE,
    CARET, TILDE, PERCENT, LESS_LESS, GREATER_GREATER,
    FOR, RETURN, PLUS_PLUS, MINUS_MINUS, EOF, UNKNOWN,
};

pub const Token = struct {
    ttype: TokenType,
    value: []const u8,
    line: usize,
};

const TokenList = struct {
    tokens: []Token,
    len: usize,
    capacity: usize,

    fn init() TokenList {
        const initial_cap = 32;
        const ptr = test_allocator.alloc(Token, initial_cap) catch return .{ .tokens = &[_]Token{}, .len = 0, .capacity = 0 };
        return .{ .tokens = ptr, .len = 0, .capacity = initial_cap };
    }

    fn append(self: *TokenList, token: Token) void {
        if (self.len >= self.capacity) {
            const new_capacity = self.capacity * 2;
            const new_tokens = test_allocator.realloc(self.tokens, new_capacity) catch return;
            self.tokens = new_tokens;
            self.capacity = new_capacity;
        }
        self.tokens[self.len] = token;
        self.len += 1;
    }

    fn deinit(self: *TokenList) void {
        if (self.capacity > 0) {
            test_allocator.free(self.tokens);
        }
    }
};

fn streq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}

fn tokenize(source: []const u8) TokenList {
    var list = TokenList.init();
    var i: usize = 0;
    var line_num: usize = 1;

    while (i < source.len) {
        const c = source[i];

        if (c == ' ' or c == '\r' or c == '\t' or c == '\n') {
            if (c == '\n') line_num += 1;
            i += 1;
            continue;
        }

        if (c == '/' and i + 1 < source.len) {
            if (source[i + 1] == '/') {
                while (i < source.len and source[i] != '\n') : (i += 1) {}
                continue;
            } else if (source[i + 1] == '*') {
                i += 2;
                while (i + 1 < source.len and !(source[i] == '*' and source[i + 1] == '/')) {
                    if (source[i] == '\n') line_num += 1;
                    i += 1;
                }
                i += 2;
                continue;
            }
        }

        if (c == '{') { list.append(.{ .ttype = .L_BRACE, .value = source[i..i+1], .line = line_num }); i += 1; continue; }
        if (c == '}') { list.append(.{ .ttype = .R_BRACE, .value = source[i..i+1], .line = line_num }); i += 1; continue; }
        if (c == '(') { list.append(.{ .ttype = .L_PAREN, .value = source[i..i+1], .line = line_num }); i += 1; continue; }
        if (c == ')') { list.append(.{ .ttype = .R_PAREN, .value = source[i..i+1], .line = line_num }); i += 1; continue; }
        if (c == ',') { list.append(.{ .ttype = .COMMA, .value = source[i..i+1], .line = line_num }); i += 1; continue; }
        if (c == ';') { list.append(.{ .ttype = .SEMICOLON, .value = source[i..i+1], .line = line_num }); i += 1; continue; }
        if (c == '.') { list.append(.{ .ttype = .DOT, .value = source[i..i+1], .line = line_num }); i += 1; continue; }

        if (c == '=') {
            if (i + 1 < source.len and source[i + 1] == '=') {
                list.append(.{ .ttype = .EQUALS_EQUALS, .value = source[i..i+2], .line = line_num }); i += 2;
            } else {
                list.append(.{ .ttype = .EQUALS, .value = source[i..i+1], .line = line_num }); i += 1;
            }
            continue;
        }
        if (c == '!') {
            if (i + 1 < source.len and source[i + 1] == '=') {
                list.append(.{ .ttype = .BANG_EQUALS, .value = source[i..i+2], .line = line_num }); i += 2;
            } else {
                list.append(.{ .ttype = .UNKNOWN, .value = source[i..i+1], .line = line_num }); i += 1;
            }
            continue;
        }
        if (c == '<') {
            if (i + 1 < source.len and source[i + 1] == '<') {
                list.append(.{ .ttype = .LESS_LESS, .value = source[i..i+2], .line = line_num }); i += 2;
            } else {
                list.append(.{ .ttype = .LESS, .value = source[i..i+1], .line = line_num }); i += 1;
            }
            continue;
        }
        if (c == '>') {
            if (i + 1 < source.len and source[i + 1] == '>') {
                list.append(.{ .ttype = .GREATER_GREATER, .value = source[i..i+2], .line = line_num }); i += 2;
            } else {
                list.append(.{ .ttype = .GREATER, .value = source[i..i+1], .line = line_num }); i += 1;
            }
            continue;
        }
        if (c == '&') { list.append(.{ .ttype = .AMPERSAND, .value = source[i..i+1], .line = line_num }); i += 1; continue; }
        if (c == '|') { list.append(.{ .ttype = .PIPE, .value = source[i..i+1], .line = line_num }); i += 1; continue; }
        if (c == '^') { list.append(.{ .ttype = .CARET, .value = source[i..i+1], .line = line_num }); i += 1; continue; }
        if (c == '~') { list.append(.{ .ttype = .TILDE, .value = source[i..i+1], .line = line_num }); i += 1; continue; }
        if (c == '%') { list.append(.{ .ttype = .PERCENT, .value = source[i..i+1], .line = line_num }); i += 1; continue; }

        if (c == '+') {
            if (i + 1 < source.len and source[i + 1] == '+') {
                list.append(.{ .ttype = .PLUS_PLUS, .value = source[i..i+2], .line = line_num }); i += 2;
            } else {
                list.append(.{ .ttype = .PLUS, .value = source[i..i+1], .line = line_num }); i += 1;
            }
            continue;
        }
        if (c == '-') {
            if (i + 1 < source.len and source[i + 1] == '-') {
                list.append(.{ .ttype = .MINUS_MINUS, .value = source[i..i+2], .line = line_num }); i += 2;
            } else {
                list.append(.{ .ttype = .MINUS, .value = source[i..i+1], .line = line_num }); i += 1;
            }
            continue;
        }
        if (c == '*') { list.append(.{ .ttype = .STAR, .value = source[i..i+1], .line = line_num }); i += 1; continue; }
        if (c == '/') { list.append(.{ .ttype = .SLASH, .value = source[i..i+1], .line = line_num }); i += 1; continue; }

        if (c == '"') {
            const start = i;
            i += 1;
            while (i < source.len and source[i] != '"') {
                if (source[i] == '\n') line_num += 1;
                i += 1;
            }
            if (i < source.len) i += 1;
            list.append(.{ .ttype = .STRING, .value = source[start..i], .line = line_num });
            continue;
        }

        if (c >= '0' and c <= '9') {
            const start = i;
            if (c == '0' and i + 1 < source.len) {
                const next = source[i + 1];
                if (next == 'x' or next == 'X') {
                    i += 2;
                    while (i < source.len and ((source[i] >= '0' and source[i] <= '9') or (source[i] >= 'A' and source[i] <= 'F') or (source[i] >= 'a' and source[i] <= 'f'))) : (i += 1) {}
                    list.append(.{ .ttype = .NUMBER, .value = source[start..i], .line = line_num });
                    continue;
                } else if (next == 'b' or next == 'B') {
                    i += 2;
                    while (i < source.len and (source[i] == '0' or source[i] == '1')) : (i += 1) {}
                    list.append(.{ .ttype = .NUMBER, .value = source[start..i], .line = line_num });
                    continue;
                }
            }
            var has_dot = false;
            while (i < source.len) : (i += 1) {
                const cur = source[i];
                if (cur >= '0' and cur <= '9') {
                    // ok
                } else if (cur == '.' and !has_dot) {
                    has_dot = true;
                } else {
                    break;
                }
            }
            list.append(.{ .ttype = .NUMBER, .value = source[start..i], .line = line_num });
            continue;
        }

        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') {
            const start = i;
            while (i < source.len and ((source[i] >= 'a' and source[i] <= 'z') or (source[i] >= 'A' and source[i] <= 'Z') or (source[i] >= '0' and source[i] <= '9') or source[i] == '_')) : (i += 1) {}
            const value = source[start..i];

            var ttype: TokenType = .IDENTIFIER;
            if (streq(value, "def")) { ttype = .DEF; }
            else if (streq(value, "import")) { ttype = .IMPORT; }
            else if (streq(value, "if")) { ttype = .IF; }
            else if (streq(value, "while")) { ttype = .WHILE; }
            else if (streq(value, "else")) { ttype = .ELSE; }
            else if (streq(value, "set")) { ttype = .SET; }
            else if (streq(value, "int")) { ttype = .INT_TYPE; }
            else if (streq(value, "string")) { ttype = .STRING_TYPE; }
            else if (streq(value, "break")) { ttype = .BREAK; }
            else if (streq(value, "continue")) { ttype = .CONTINUE; }
            else if (streq(value, "for")) { ttype = .FOR; }
            else if (streq(value, "return")) { ttype = .RETURN; }

            list.append(.{ .ttype = ttype, .value = value, .line = line_num });
            continue;
        }

        list.append(.{ .ttype = .UNKNOWN, .value = source[i..i+1], .line = line_num });
        i += 1;
    }

    list.append(.{ .ttype = .EOF, .value = "", .line = line_num });
    return list;
}

// --- Tests ---

test "lexer: empty input produces EOF only" {
    var list = tokenize("");
    defer list.deinit();
    try std.testing.expectEqual(1, list.len);
    try std.testing.expectEqual(TokenType.EOF, list.tokens[0].ttype);
}

test "lexer: whitespace only produces EOF" {
    var list = tokenize("  \t\n  ");
    defer list.deinit();
    try std.testing.expectEqual(1, list.len);
    try std.testing.expectEqual(TokenType.EOF, list.tokens[0].ttype);
}

test "lexer: single line comment" {
    var list = tokenize("// comment\n");
    defer list.deinit();
    try std.testing.expectEqual(1, list.len);
    try std.testing.expectEqual(TokenType.EOF, list.tokens[0].ttype);
}

test "lexer: block comment" {
    var list = tokenize("/* comment */");
    defer list.deinit();
    try std.testing.expectEqual(1, list.len);
    try std.testing.expectEqual(TokenType.EOF, list.tokens[0].ttype);
}

test "lexer: block comment not nested (first */ closes)" {
    var list = tokenize("/* outer /* inner */ still outer */");
    defer list.deinit();
    // After first */: still, outer, *(STAR), /(SLASH), EOF = 5
    try std.testing.expectEqual(5, list.len);
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "still");
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[1].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "outer");
    try std.testing.expectEqual(TokenType.STAR, list.tokens[2].ttype);
    try std.testing.expectEqual(TokenType.SLASH, list.tokens[3].ttype);
}

test "lexer: unterminated block comment at EOF" {
    var list = tokenize("/* unterminated");
    defer list.deinit();
    try std.testing.expectEqual(1, list.len);
    try std.testing.expectEqual(TokenType.EOF, list.tokens[0].ttype);
}

test "lexer: block comment with newlines increments line counter" {
    var list = tokenize("/* line 1\nline 2 */\nfoo");
    defer list.deinit();
    try std.testing.expect(list.len >= 2);
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "foo");
    try std.testing.expectEqual(3, list.tokens[0].line);
}

test "lexer: identifiers" {
    var list = tokenize("foo bar _test __private");
    defer list.deinit();
    try std.testing.expectEqual(5, list.len);
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "foo");
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "bar");
    try std.testing.expectEqualSlices(u8, list.tokens[2].value, "_test");
    try std.testing.expectEqualSlices(u8, list.tokens[3].value, "__private");
}

test "lexer: numbers - decimal" {
    var list = tokenize("42 0 99999");
    defer list.deinit();
    try std.testing.expectEqual(4, list.len);
    try std.testing.expectEqual(TokenType.NUMBER, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "42");
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "0");
    try std.testing.expectEqualSlices(u8, list.tokens[2].value, "99999");
}

test "lexer: numbers - hex" {
    var list = tokenize("0xFF 0xABCD 0x12345678");
    defer list.deinit();
    try std.testing.expectEqual(4, list.len);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "0xFF");
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "0xABCD");
    try std.testing.expectEqualSlices(u8, list.tokens[2].value, "0x12345678");
}

test "lexer: numbers - hex uppercase prefix" {
    var list = tokenize("0X10");
    defer list.deinit();
    try std.testing.expectEqual(2, list.len);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "0X10");
}

test "lexer: numbers - binary" {
    var list = tokenize("0b1010 0B0101");
    defer list.deinit();
    try std.testing.expectEqual(3, list.len);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "0b1010");
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "0B0101");
}

test "lexer: numbers - floating point" {
    var list = tokenize("3.14 0.5 1.0");
    defer list.deinit();
    try std.testing.expectEqual(4, list.len);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "3.14");
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "0.5");
    try std.testing.expectEqualSlices(u8, list.tokens[2].value, "1.0");
}

test "lexer: numbers - decimal followed by identifier" {
    var list = tokenize("123abc");
    defer list.deinit();
    try std.testing.expectEqual(3, list.len);
    try std.testing.expectEqual(TokenType.NUMBER, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "123");
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[1].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "abc");
}

test "lexer: strings - simple" {
    var list = tokenize("\"hello\"");
    defer list.deinit();
    try std.testing.expectEqual(2, list.len);
    try std.testing.expectEqual(TokenType.STRING, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "\"hello\"");
}

test "lexer: strings - multiline" {
    var list = tokenize("\"line1\nline2\"");
    defer list.deinit();
    try std.testing.expectEqual(2, list.len);
    try std.testing.expectEqual(TokenType.STRING, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "\"line1\nline2\"");
}

test "lexer: unterminated string" {
    var list = tokenize("\"unterminated");
    defer list.deinit();
    try std.testing.expectEqual(2, list.len);
    try std.testing.expectEqual(TokenType.STRING, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "\"unterminated");
}

test "lexer: strings - empty" {
    var list = tokenize("\"\"");
    defer list.deinit();
    try std.testing.expectEqual(2, list.len);
    try std.testing.expectEqual(TokenType.STRING, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "\"\"");
}

test "lexer: keywords - def import if while else" {
    var list = tokenize("def import if while else");
    defer list.deinit();
    try std.testing.expectEqual(6, list.len);
    try std.testing.expectEqual(TokenType.DEF, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.IMPORT, list.tokens[1].ttype);
    try std.testing.expectEqual(TokenType.IF, list.tokens[2].ttype);
    try std.testing.expectEqual(TokenType.WHILE, list.tokens[3].ttype);
    try std.testing.expectEqual(TokenType.ELSE, list.tokens[4].ttype);
}

test "lexer: keywords - set int string break continue for return" {
    var list = tokenize("set int string break continue for return");
    defer list.deinit();
    // 7 keywords + EOF = 8 tokens
    try std.testing.expectEqual(8, list.len);
    try std.testing.expectEqual(TokenType.SET, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.INT_TYPE, list.tokens[1].ttype);
    try std.testing.expectEqual(TokenType.STRING_TYPE, list.tokens[2].ttype);
    try std.testing.expectEqual(TokenType.BREAK, list.tokens[3].ttype);
    try std.testing.expectEqual(TokenType.CONTINUE, list.tokens[4].ttype);
    try std.testing.expectEqual(TokenType.FOR, list.tokens[5].ttype);
    try std.testing.expectEqual(TokenType.RETURN, list.tokens[6].ttype);
}

test "lexer: keywords are case-sensitive" {
    var list = tokenize("If While Else");
    defer list.deinit();
    try std.testing.expectEqual(4, list.len);
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[1].ttype);
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[2].ttype);
}

test "lexer: braces and parens" {
    var list = tokenize("{}()");
    defer list.deinit();
    try std.testing.expectEqual(5, list.len);
    try std.testing.expectEqual(TokenType.L_BRACE, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.R_BRACE, list.tokens[1].ttype);
    try std.testing.expectEqual(TokenType.L_PAREN, list.tokens[2].ttype);
    try std.testing.expectEqual(TokenType.R_PAREN, list.tokens[3].ttype);
}

test "lexer: punctuation" {
    var list = tokenize(",;.");
    defer list.deinit();
    try std.testing.expectEqual(4, list.len);
    try std.testing.expectEqual(TokenType.COMMA, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.SEMICOLON, list.tokens[1].ttype);
    try std.testing.expectEqual(TokenType.DOT, list.tokens[2].ttype);
}

test "lexer: single-char operators" {
    var list = tokenize("+ - * / % & | ^ ~ < > !");
    defer list.deinit();
    // 12 single-char ops + EOF = 13
    try std.testing.expectEqual(13, list.len);
    try std.testing.expectEqual(TokenType.PLUS, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.MINUS, list.tokens[1].ttype);
    try std.testing.expectEqual(TokenType.STAR, list.tokens[2].ttype);
    try std.testing.expectEqual(TokenType.SLASH, list.tokens[3].ttype);
    try std.testing.expectEqual(TokenType.PERCENT, list.tokens[4].ttype);
    try std.testing.expectEqual(TokenType.AMPERSAND, list.tokens[5].ttype);
    try std.testing.expectEqual(TokenType.PIPE, list.tokens[6].ttype);
    try std.testing.expectEqual(TokenType.CARET, list.tokens[7].ttype);
    try std.testing.expectEqual(TokenType.TILDE, list.tokens[8].ttype);
    try std.testing.expectEqual(TokenType.LESS, list.tokens[9].ttype);
    try std.testing.expectEqual(TokenType.GREATER, list.tokens[10].ttype);
    try std.testing.expectEqual(TokenType.UNKNOWN, list.tokens[11].ttype); // ! alone
}

test "lexer: two-char operators" {
    // Note: && || <= >= are NOT two-char operators in Nova lexer
    // Only == != << >> ++ -- are
    var list = tokenize("== != << >> ++ --");
    defer list.deinit();
    try std.testing.expectEqual(7, list.len);
    try std.testing.expectEqual(TokenType.EQUALS_EQUALS, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.BANG_EQUALS, list.tokens[1].ttype);
    try std.testing.expectEqual(TokenType.LESS_LESS, list.tokens[2].ttype);
    try std.testing.expectEqual(TokenType.GREATER_GREATER, list.tokens[3].ttype);
    try std.testing.expectEqual(TokenType.PLUS_PLUS, list.tokens[4].ttype);
    try std.testing.expectEqual(TokenType.MINUS_MINUS, list.tokens[5].ttype);
}

test "lexer: equals vs equals_equals" {
    var list = tokenize("= ==");
    defer list.deinit();
    try std.testing.expectEqual(3, list.len);
    try std.testing.expectEqual(TokenType.EQUALS, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.EQUALS_EQUALS, list.tokens[1].ttype);
}

test "lexer: less vs less_less" {
    var list = tokenize("< <<");
    defer list.deinit();
    try std.testing.expectEqual(3, list.len);
    try std.testing.expectEqual(TokenType.LESS, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.LESS_LESS, list.tokens[1].ttype);
}

test "lexer: greater vs greater_greater" {
    var list = tokenize("> >>");
    defer list.deinit();
    try std.testing.expectEqual(3, list.len);
    try std.testing.expectEqual(TokenType.GREATER, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.GREATER_GREATER, list.tokens[1].ttype);
}

test "lexer: plus vs plus_plus" {
    var list = tokenize("+ ++");
    defer list.deinit();
    try std.testing.expectEqual(3, list.len);
    try std.testing.expectEqual(TokenType.PLUS, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.PLUS_PLUS, list.tokens[1].ttype);
}

test "lexer: minus vs minus_minus" {
    var list = tokenize("- --");
    defer list.deinit();
    try std.testing.expectEqual(3, list.len);
    try std.testing.expectEqual(TokenType.MINUS, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.MINUS_MINUS, list.tokens[1].ttype);
}

test "lexer: bang vs bang_equals" {
    var list = tokenize("! !=");
    defer list.deinit();
    try std.testing.expectEqual(3, list.len);
    try std.testing.expectEqual(TokenType.UNKNOWN, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.BANG_EQUALS, list.tokens[1].ttype);
}

test "lexer: complex program" {
    const src =
    \\def foo(a, b) {
    \\    set x = a + b
    \\    if x > 10
    \\        return x
    \\}
    ;
    var list = tokenize(src);
    defer list.deinit();

    // Tokens: def foo ( a , b ) { set x = a + b if x > 10 return x } EOF
    // Index:  0  1  2 3 4 5 6 7 8 9 = ...
    try std.testing.expectEqual(TokenType.DEF, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "foo");
    try std.testing.expectEqual(TokenType.L_PAREN, list.tokens[2].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[3].value, "a");
    try std.testing.expectEqual(TokenType.COMMA, list.tokens[4].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[5].value, "b");
    try std.testing.expectEqual(TokenType.R_PAREN, list.tokens[6].ttype);
    try std.testing.expectEqual(TokenType.L_BRACE, list.tokens[7].ttype);
    try std.testing.expectEqual(TokenType.SET, list.tokens[8].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[9].value, "x");
    try std.testing.expectEqual(TokenType.EQUALS, list.tokens[10].ttype);
    try std.testing.expectEqual(TokenType.IF, list.tokens[14].ttype);
    try std.testing.expectEqual(TokenType.GREATER, list.tokens[16].ttype);
}

test "lexer: line numbers track correctly" {
    var list = tokenize("line1\nline2\nline3");
    defer list.deinit();
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[0].ttype);
    try std.testing.expectEqual(1, list.tokens[0].line);
    try std.testing.expectEqual(2, list.tokens[1].line);
    try std.testing.expectEqual(3, list.tokens[2].line);
}

test "lexer: slash operator vs comment" {
    var list = tokenize("/  // comment");
    defer list.deinit();
    try std.testing.expectEqual(2, list.len);
    try std.testing.expectEqual(TokenType.SLASH, list.tokens[0].ttype);
}

test "lexer: multiple comments between code" {
    var list = tokenize("a // comment\n b /* block */ c");
    defer list.deinit();
    try std.testing.expectEqual(4, list.len);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "a");
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "b");
    try std.testing.expectEqualSlices(u8, list.tokens[2].value, "c");
}

test "lexer: unknown character" {
    var list = tokenize("@#");
    defer list.deinit();
    try std.testing.expectEqual(3, list.len);
    try std.testing.expectEqual(TokenType.UNKNOWN, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "@");
    try std.testing.expectEqual(TokenType.UNKNOWN, list.tokens[1].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "#");
}

test "lexer: number followed immediately by identifier" {
    var list = tokenize("42x");
    defer list.deinit();
    try std.testing.expectEqual(3, list.len);
    try std.testing.expectEqual(TokenType.NUMBER, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "42");
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[1].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "x");
}

test "lexer: identifier starting with underscore then digits" {
    var list = tokenize("_123 _a_b");
    defer list.deinit();
    try std.testing.expectEqual(3, list.len);
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[0].ttype);
    try std.testing.expectEqualSlices(u8, list.tokens[0].value, "_123");
    try std.testing.expectEqualSlices(u8, list.tokens[1].value, "_a_b");
}

test "lexer: token line tracking with comments" {
    var list = tokenize("// comment\nfoo");
    defer list.deinit();
    try std.testing.expectEqual(2, list.len);
    try std.testing.expectEqual(TokenType.IDENTIFIER, list.tokens[0].ttype);
    try std.testing.expectEqual(2, list.tokens[0].line);
}

test "lexer: EOF at end of complex script" {
    var list = tokenize("set x = 1\nprint(x)");
    defer list.deinit();
    // set x = 1 print ( x ) EOF — 8 tokens
    try std.testing.expect(list.tokens[list.len - 1].ttype == TokenType.EOF);
    try std.testing.expectEqual(2, list.tokens[list.len - 1].line);
}

test "lexer: all keywords tokenized" {
    var list = tokenize("def if while else set int string break continue for return");
    defer list.deinit();
    // 11 keywords + EOF = 12
    try std.testing.expectEqual(12, list.len);
    try std.testing.expectEqual(TokenType.DEF, list.tokens[0].ttype);
    try std.testing.expectEqual(TokenType.RETURN, list.tokens[10].ttype);
    try std.testing.expectEqual(TokenType.EOF, list.tokens[11].ttype);
}
