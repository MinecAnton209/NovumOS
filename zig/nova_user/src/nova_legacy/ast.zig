const hash_table = @import("hash_table.zig");

pub const NodeType = enum {
    program,
    var_decl,
    assign,
    func_call,
    bin_op,
    unary_op,
    int_lit,
    float_lit,
    str_lit,
    ident,
    block,
    if_stmt,
    while_stmt,
    for_stmt,
    func_def,
    return_stmt,
    break_stmt,
    continue_stmt,
    import_stmt,
};

pub const BinOp = enum {
    add,
    sub,
    mul,
    div,
    mod,
    eq,
    neq,
    lt,
    gt,
    le,
    ge,
    bit_and,
    bit_or,
    bit_xor,
    shl,
    shr,
};

pub const UnaryOp = enum {
    neg,
    bit_not,
};

pub const Node = struct {
    node_type: NodeType,
    resolved_type: ?hash_table.VariableType = null,
    line: usize,

    str_val: []const u8 = "",

    int_val: i32 = 0,
    float_val: f32 = 0.0,

    bin_op: BinOp = undefined,
    unary_op: UnaryOp = undefined,

    left: ?*Node = null,
    right: ?*Node = null,

    stmts: ?[*]*Node = null,
    stmt_count: usize = 0,

    decl_type: ?hash_table.VariableType = null,
};
