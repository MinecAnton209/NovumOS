// Nova Language - Lexer
const common = @import("common.zig");
const memory = @import("../memory.zig");

pub const TokenType = enum {
    DEF,
    IMPORT,
    IDENTIFIER,
    NUMBER,
    STRING,
    EQUALS,
    IF,
    WHILE,
    ELSE,
    SET,
    INT_TYPE,
    STRING_TYPE,
    L_BRACE,
    R_BRACE,
    L_PAREN,
    R_PAREN,
    COMMA,
    SEMICOLON,
    PLUS,
    MINUS,
    STAR,
    SLASH,
    BANG_EQUALS,
    EQUALS_EQUALS,
    LESS,
    GREATER,
    BREAK,
    CONTINUE,
    EOF,
    UNKNOWN,
};

pub const Token = struct {
    ttype: TokenType,
    value: []const u8,
    line: usize,
};

pub const TokenList = struct {
    tokens: [*]Token,
    len: usize,
    capacity: usize,

    pub fn init() TokenList {
        const initial_cap = 32;
        const ptr = memory.heap.alloc(initial_cap * @sizeOf(Token)) orelse {
            return .{ .tokens = undefined, .len = 0, .capacity = 0 };
        };
        return .{
            .tokens = @ptrCast(@alignCast(ptr)),
            .len = 0,
            .capacity = initial_cap,
        };
    }

    pub fn append(self: *TokenList, token: Token) void {
        if (self.capacity == 0) return;
        if (self.len >= self.capacity) {
            const new_capacity = self.capacity * 2;
            const new_ptr = memory.heap.alloc(new_capacity * @sizeOf(Token)) orelse return;
            const new_tokens: [*]Token = @ptrCast(@alignCast(new_ptr));

            for (0..self.len) |i| {
                new_tokens[i] = self.tokens[i];
            }

            // Note: In this simple heap allocator, we don't have 'realloc'.
            // and we don't have a way to free the old pointer easily if we don't track it well.
            // But for a script execution, it might be fine for now.
            // Actually, we SHOULD free it if we can.
            memory.heap.free(@ptrCast(self.tokens));
            self.tokens = new_tokens;
            self.capacity = new_capacity;
        }
        self.tokens[self.len] = token;
        self.len += 1;
    }

    pub fn deinit(self: *TokenList) void {
        if (self.capacity > 0) {
            memory.heap.free(@ptrCast(self.tokens));
        }
    }
};

pub fn tokenize(source: []const u8) TokenList {
    var list = TokenList.init();
    var i: usize = 0;
    var line_num: usize = 1;

    while (i < source.len) {
        const c = source[i];

        // Skip whitespace
        if (c == ' ' or c == '\r' or c == '\t' or c == '\n') {
            if (c == '\n') line_num += 1;
            i += 1;
            continue;
        }

        // Comments
        if (c == '/' and i + 1 < source.len) {
            if (source[i + 1] == '/') {
                // Single line comment
                while (i < source.len and source[i] != '\n') : (i += 1) {}
                continue; // Let the main loop handle the \n and increment line_num
            } else if (source[i + 1] == '*') {
                // Block comment
                i += 2;
                while (i + 1 < source.len and !(source[i] == '*' and source[i + 1] == '/')) {
                    if (source[i] == '\n') line_num += 1;
                    i += 1;
                }
                i += 2; // skip */
                continue;
            }
        }

        // Braces and parens
        if (c == '{') {
            list.append(.{ .ttype = .L_BRACE, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }
        if (c == '}') {
            list.append(.{ .ttype = .R_BRACE, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }
        if (c == '(') {
            list.append(.{ .ttype = .L_PAREN, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }
        if (c == ')') {
            list.append(.{ .ttype = .R_PAREN, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }
        if (c == ',') {
            list.append(.{ .ttype = .COMMA, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }
        if (c == ';') {
            list.append(.{ .ttype = .SEMICOLON, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }

        // Operators
        if (c == '=') {
            if (i + 1 < source.len and source[i + 1] == '=') {
                list.append(.{ .ttype = .EQUALS_EQUALS, .value = source[i .. i + 2], .line = line_num });
                i += 2;
            } else {
                list.append(.{ .ttype = .EQUALS, .value = source[i .. i + 1], .line = line_num });
                i += 1;
            }
            continue;
        }
        if (c == '!') {
            if (i + 1 < source.len and source[i + 1] == '=') {
                list.append(.{ .ttype = .BANG_EQUALS, .value = source[i .. i + 2], .line = line_num });
                i += 2;
            } else {
                list.append(.{ .ttype = .UNKNOWN, .value = source[i .. i + 1], .line = line_num });
                i += 1;
            }
            continue;
        }
        if (c == '<') {
            list.append(.{ .ttype = .LESS, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }
        if (c == '>') {
            list.append(.{ .ttype = .GREATER, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }
        if (c == '+') {
            list.append(.{ .ttype = .PLUS, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }
        if (c == '-') {
            list.append(.{ .ttype = .MINUS, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }
        if (c == '*') {
            list.append(.{ .ttype = .STAR, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }
        if (c == '/') {
            list.append(.{ .ttype = .SLASH, .value = source[i .. i + 1], .line = line_num });
            i += 1;
            continue;
        }

        // Strings
        if (c == '"') {
            const start = i;
            i += 1;
            while (i < source.len and source[i] != '"') {
                if (source[i] == '\n') line_num += 1;
                i += 1;
            }
            if (i < source.len) i += 1; // consume closing quote
            list.append(.{ .ttype = .STRING, .value = source[start..i], .line = line_num });
            continue;
        }

        // Numbers
        if (c >= '0' and c <= '9') {
            const start = i;
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

        // Identifiers and Keywords
        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') {
            const start = i;
            while (i < source.len and ((source[i] >= 'a' and source[i] <= 'z') or (source[i] >= 'A' and source[i] <= 'Z') or (source[i] >= '0' and source[i] <= '9') or source[i] == '_')) : (i += 1) {}
            const value = source[start..i];

            var ttype: TokenType = .IDENTIFIER;
            if (common.streq(value, "def")) {
                ttype = .DEF;
            } else if (common.streq(value, "import")) {
                ttype = .IMPORT;
            } else if (common.streq(value, "if")) {
                ttype = .IF;
            } else if (common.streq(value, "while")) {
                ttype = .WHILE;
            } else if (common.streq(value, "else")) {
                ttype = .ELSE;
            } else if (common.streq(value, "set")) {
                ttype = .SET;
            } else if (common.streq(value, "int")) {
                ttype = .INT_TYPE;
            } else if (common.streq(value, "string")) {
                ttype = .STRING_TYPE;
            } else if (common.streq(value, "break")) {
                ttype = .BREAK;
            } else if (common.streq(value, "continue")) {
                ttype = .CONTINUE;
            }

            list.append(.{ .ttype = ttype, .value = value, .line = line_num });
            continue;
        }

        // Unknown character
        list.append(.{ .ttype = .UNKNOWN, .value = source[i .. i + 1], .line = line_num });
        i += 1;
    }

    list.append(.{ .ttype = .EOF, .value = "", .line = line_num });
    return list;
}
