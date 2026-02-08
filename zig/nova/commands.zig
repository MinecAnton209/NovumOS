// Nova Language - Commands execution
const common = @import("common.zig");
const parser = @import("parser.zig");
const interpreter = @import("interpreter.zig");
const shell = @import("../shell.zig");

// --- Variable Storage ---
const MAX_VARS = 16;
const MAX_VAR_NAME = 16;
const MAX_VAL_LEN = 64;

const VarType = enum {
    string,
    int,
};

const Variable = struct {
    name: [MAX_VAR_NAME]u8,
    name_len: usize,
    value: [MAX_VAL_LEN]u8, // String storage
    val_len: usize,
    int_val: i32, // Int storage
    vtype: VarType,
};

var variables: [MAX_VARS]Variable = undefined;
var var_count: usize = 0;
var int_conv_buf: [32]u8 = undefined;
var term_buffer: [512]u8 = [_]u8{0} ** 512;
var global_result_buffer: [512]u8 = [_]u8{0} ** 512;

// Script arguments storage
const MAX_SCRIPT_ARGS = 8;
const MAX_ARG_LEN = 64;
pub var script_args: [MAX_SCRIPT_ARGS][MAX_ARG_LEN]u8 = [_][MAX_ARG_LEN]u8{[_]u8{0} ** MAX_ARG_LEN} ** MAX_SCRIPT_ARGS;
pub var script_args_len: [MAX_SCRIPT_ARGS]usize = [_]usize{0} ** MAX_SCRIPT_ARGS;
pub var script_argc: usize = 0;

pub fn setScriptArgs(args: []const []const u8) void {
    script_argc = @min(args.len, MAX_SCRIPT_ARGS);
    for (0..script_argc) |i| {
        const len = @min(args[i].len, MAX_ARG_LEN);
        common.copy(script_args[i][0..], args[i][0..len]);
        script_args_len[i] = len;
    }
}

pub fn clearScriptArgs() void {
    script_argc = 0;
    for (0..MAX_SCRIPT_ARGS) |i| {
        script_args_len[i] = 0;
    }
}

// --- Helper Functions ---

fn trim(s: []const u8) []const u8 {
    if (s.len == 0) return s;
    var start: usize = 0;
    while (start < s.len and s[start] == ' ') : (start += 1) {}
    var end: usize = s.len;
    while (end > start and s[end - 1] == ' ') : (end -= 1) {}
    return s[start..end];
}

fn findVariable(name: []const u8) ?*Variable {
    var i: usize = 0;
    while (i < var_count) : (i += 1) {
        if (common.streq(variables[i].name[0..variables[i].name_len], name)) {
            return &variables[i];
        }
    }
    return null;
}

fn setVariable(name: []const u8, val: []const u8, vtype: VarType, int_val: i32) void {
    if (findVariable(name)) |v| {
        // Update
        if (vtype == .string) {
            const copy_len = if (val.len > MAX_VAL_LEN) MAX_VAL_LEN else val.len;
            common.copy(v.value[0..], val[0..copy_len]);
            v.val_len = copy_len;
        } else {
            v.int_val = int_val;
        }
        v.vtype = vtype;
    } else {
        // Create new
        if (var_count < MAX_VARS) {
            var v = &variables[var_count];

            const name_copy_len = if (name.len > MAX_VAR_NAME) MAX_VAR_NAME else name.len;
            common.copy(v.name[0..], name[0..name_copy_len]);
            v.name_len = name_copy_len;

            if (vtype == .string) {
                const val_copy_len = if (val.len > MAX_VAL_LEN) MAX_VAL_LEN else val.len;
                common.copy(v.value[0..], val[0..val_copy_len]);
                v.val_len = val_copy_len;
            } else {
                v.int_val = int_val;
            }
            v.vtype = vtype;

            var_count += 1;
        } else {
            common.printZ("Error: Too many variables\n");
        }
    }
}

// Result of an evaluation
const EvalResult = struct {
    str_val: []const u8,
    int_val: i32,
    etype: VarType,
};

// Get value of a single term (literal or variable)
fn getValue(raw_term: []const u8) EvalResult {
    const term = trim(raw_term);
    if (term.len == 0) return .{ .str_val = "", .int_val = 0, .etype = .string };

    // Literal String
    if (term[0] == '"') {
        var end = term.len;
        if (term.len > 1 and term[term.len - 1] == '"') {
            end = term.len - 1;
        }
        if (end > 1) {
            return .{ .str_val = term[1..end], .int_val = 0, .etype = .string };
        }
        return .{ .str_val = "", .int_val = 0, .etype = .string };
    }

    // Variable
    if (findVariable(term)) |v| {
        if (v.vtype == .string) {
            return .{ .str_val = v.value[0..v.val_len], .int_val = 0, .etype = .string };
        } else {
            return .{ .str_val = "", .int_val = v.int_val, .etype = .int };
        }
    }

    // Literal Int
    // Assume if it starts with digit or -, and parses, it's int
    if ((term[0] >= '0' and term[0] <= '9') or term[0] == '-') {
        return .{ .str_val = "", .int_val = common.parseInt(term), .etype = .int };
    }

    return .{ .str_val = "", .int_val = 0, .etype = .string };
}

// Basic Left-to-Right Evaluator with limited precedence for simplicity
// Supports + - * /
// WARNING: No complex precedence supported yet (e.g. 1 + 2 * 3 will be evaluated as (1+2)*3)
// For a simple toy OS language this might be acceptable unless full math parser is needed.
// To support full precedence, we need a better parser. Given constraints, let's try a simple L-R split.

fn evaluateTerm(raw_term: []const u8) EvalResult {
    const term = trim(raw_term);
    if (term.len == 0) return .{ .str_val = "", .int_val = 0, .etype = .int };

    // Check for parens
    if (term.len >= 2 and term[0] == '(' and term[term.len - 1] == ')') {
        // We assume valid nesting from the splitter, but let's be safe later if needed.
        // For now, strip and recurse.
        return evaluateExpression(term[1 .. term.len - 1]);
    }

    if (common.startsWith(term, "read(")) {
        if (term[term.len - 1] == ')') {
            const path_expr = term[5 .. term.len - 1];
            const path_res = evaluateExpression(path_expr);
            if (path_res.etype == .string) {
                const drive = getDrive();
                if (common.fat.read_bpb(drive)) |bpb| {
                    const r_len = common.fat.read_file(drive, bpb, common.global_common.current_dir_cluster, path_res.str_val, &term_buffer);
                    if (r_len >= 0) {
                        return .{ .str_val = term_buffer[0..@intCast(r_len)], .int_val = 0, .etype = .string };
                    }
                }
            }
        }
        return .{ .str_val = "", .int_val = 0, .etype = .string };
    }

    if (common.startsWith(term, "random(")) {
        if (term[term.len - 1] == ')') {
            const args = splitArgs(term[7 .. term.len - 1]);
            if (args.count >= 2) {
                const min_v = evaluateExpression(args.args[0]);
                const max_v = evaluateExpression(args.args[1]);
                return .{ .str_val = "", .int_val = common.global_common.get_random(min_v.int_val, max_v.int_val), .etype = .int };
            }
        }
        return .{ .str_val = "", .int_val = 0, .etype = .int };
    }

    if (common.startsWith(term, "abs(")) {
        if (term[term.len - 1] == ')') {
            const res = evaluateExpression(term[4 .. term.len - 1]);
            return .{ .str_val = "", .int_val = common.global_common.math_abs(res.int_val), .etype = .int };
        }
    }
    if (common.startsWith(term, "min(")) {
        if (term[term.len - 1] == ')') {
            const args = splitArgs(term[4 .. term.len - 1]);
            if (args.count >= 2) {
                const a = evaluateExpression(args.args[0]);
                const b = evaluateExpression(args.args[1]);
                return .{ .str_val = "", .int_val = common.global_common.math_min(a.int_val, b.int_val), .etype = .int };
            }
        }
    }
    if (common.startsWith(term, "max(")) {
        if (term[term.len - 1] == ')') {
            const args = splitArgs(term[4 .. term.len - 1]);
            if (args.count >= 2) {
                const a = evaluateExpression(args.args[0]);
                const b = evaluateExpression(args.args[1]);
                return .{ .str_val = "", .int_val = common.global_common.math_max(a.int_val, b.int_val), .etype = .int };
            }
        }
    }

    // Trigonometry approximations (scaled by 100, input in degrees)
    if (common.startsWith(term, "sin(")) {
        if (term[term.len - 1] == ')') {
            const res = evaluateExpression(term[4 .. term.len - 1]);
            return .{ .str_val = "", .int_val = approx_sin(res.int_val), .etype = .int };
        }
    }
    if (common.startsWith(term, "cos(")) {
        if (term[term.len - 1] == ')') {
            const res = evaluateExpression(term[4 .. term.len - 1]);
            return .{ .str_val = "", .int_val = approx_sin(res.int_val + 90), .etype = .int };
        }
    }
    if (common.startsWith(term, "tg(") or common.startsWith(term, "tan(")) {
        const start_idx: usize = if (common.startsWith(term, "tg(")) 3 else 4;
        if (term[term.len - 1] == ')') {
            const res = evaluateExpression(term[start_idx .. term.len - 1]);
            const s = approx_sin(res.int_val);
            const c = approx_sin(res.int_val + 90);
            if (c == 0) return .{ .str_val = "", .int_val = 9999, .etype = .int };
            return .{ .str_val = "", .int_val = @divTrunc(s * 100, c), .etype = .int };
        }
    }
    if (common.startsWith(term, "ctg(")) {
        if (term[term.len - 1] == ')') {
            const res = evaluateExpression(term[4 .. term.len - 1]);
            const s = approx_sin(res.int_val);
            const c = approx_sin(res.int_val + 90);
            if (s == 0) return .{ .str_val = "", .int_val = 9999, .etype = .int };
            return .{ .str_val = "", .int_val = @divTrunc(c * 100, s), .etype = .int };
        }
    }

    if (common.startsWith(term, "input(")) {
        if (term[term.len - 1] == ')') {
            const prompt_expr = term[6 .. term.len - 1];
            const prompt_res = evaluateExpression(prompt_expr);
            if (prompt_res.etype == .string) {
                common.printZ(prompt_res.str_val);
            } else {
                const s = common.intToString(prompt_res.int_val, &int_conv_buf);
                common.printZ(s);
            }
        }

        // Use interpreter's global buffer temporarily or a local one
        // Let's use a local one for safety during expression evaluation
        var input_buf: [64]u8 = [_]u8{0} ** 64;
        const len = interpreter.readInput(&input_buf);

        const final_input = input_buf[0..len];
        // Try to see if it's an int
        if (len > 0 and ((final_input[0] >= '0' and final_input[0] <= '9') or final_input[0] == '-')) {
            return .{ .str_val = final_input, .int_val = common.parseInt(final_input), .etype = .int };
        }

        // Return as string
        // Copy to persistent storage
        common.copy(global_result_buffer[0..], final_input);
        return .{ .str_val = global_result_buffer[0..len], .int_val = 0, .etype = .string };
    }

    // argc() - returns number of script arguments
    if (common.std_mem_eql(term, "argc()")) {
        return .{ .str_val = "", .int_val = @intCast(script_argc), .etype = .int };
    }

    // args(n) - returns nth argument as string
    if (common.startsWith(term, "args(")) {
        if (term[term.len - 1] == ')') {
            const idx_expr = term[5 .. term.len - 1];
            const idx_res = evaluateExpression(idx_expr);
            if (idx_res.etype == .int and idx_res.int_val >= 0 and idx_res.int_val < script_argc) {
                const idx: usize = @intCast(idx_res.int_val);
                const arg = script_args[idx][0..script_args_len[idx]];
                // Copy to global buffer for persistence
                common.copy(global_result_buffer[0..], arg);
                return .{ .str_val = global_result_buffer[0..script_args_len[idx]], .int_val = 0, .etype = .string };
            }
            // Return empty string if index out of bounds
            return .{ .str_val = "", .int_val = 0, .etype = .string };
        }
    }

    return getValue(term);
}

fn evaluateExpression(expr_in: []const u8) EvalResult {
    var pos: usize = 0;
    var last_op: u8 = 0;
    var start: usize = 0;
    var depth: i32 = 0;
    var in_quotes: bool = false;

    var accum_int: i32 = 0;
    var eval_buffer: [256]u8 = [_]u8{0} ** 256;
    var accum_str_len: usize = 0;
    var current_type: VarType = .int;

    while (pos <= expr_in.len) {
        var is_op = false;
        var c: u8 = 0;

        if (pos < expr_in.len) {
            c = expr_in[pos];
            if (c == '"') in_quotes = !in_quotes;

            if (!in_quotes) {
                if (c == '(') {
                    depth += 1;
                } else if (c == ')') {
                    depth -= 1;
                } else if (depth == 0) {
                    if (c == '+' or c == '-' or c == '*' or c == '/') {
                        is_op = true;
                    } else if (c == '=' and pos + 1 < expr_in.len and expr_in[pos + 1] == '=') {
                        is_op = true;
                    } else if (c == '!' and pos + 1 < expr_in.len and expr_in[pos + 1] == '=') {
                        is_op = true;
                    } else if (c == '<' or c == '>') {
                        is_op = true;
                    }
                }
            }
        }

        if (depth == 0 and !in_quotes and (pos == expr_in.len or is_op)) {
            const part = trim(expr_in[start..pos]);
            if (part.len > 0 or pos == expr_in.len) {
                const val = evaluateTerm(part);

                if (last_op == 0) {
                    current_type = val.etype;
                    if (current_type == .int) {
                        accum_int = val.int_val;
                    } else {
                        common.copy(eval_buffer[0..], val.str_val);
                        accum_str_len = val.str_val.len;
                    }
                } else {
                    if (current_type == .int and val.etype == .int) {
                        if (last_op == '+') {
                            accum_int += val.int_val;
                        } else if (last_op == '-') {
                            accum_int -= val.int_val;
                        } else if (last_op == '*') {
                            accum_int *= val.int_val;
                        } else if (last_op == '/') {
                            if (val.int_val != 0) accum_int = @divTrunc(accum_int, val.int_val) else accum_int = 0;
                        } else if (last_op == '=') {
                            accum_int = if (accum_int == val.int_val) 1 else 0;
                        } else if (last_op == '!') {
                            accum_int = if (accum_int != val.int_val) 1 else 0;
                        } else if (last_op == '<') {
                            accum_int = if (accum_int < val.int_val) 1 else 0;
                        } else if (last_op == '>') {
                            accum_int = if (accum_int > val.int_val) 1 else 0;
                        }
                    } else if (current_type == .string) {
                        if (last_op == '+') {
                            // We need to be careful: evaluateTerm might have used global_result_buffer
                            // So we copy our current accum_str to a temp buffer if needed
                            var to_add_buf: [64]u8 = [_]u8{0} ** 64;
                            var to_add: []const u8 = "";

                            if (val.etype == .string) {
                                // Copy to temp because next evaluateTerm/Expression might overwrite global_result_buffer
                                const t_len = if (val.str_val.len > 64) 64 else val.str_val.len;
                                for (0..t_len) |j| to_add_buf[j] = val.str_val[j];
                                to_add = to_add_buf[0..t_len];
                            } else {
                                to_add = common.intToString(val.int_val, &int_conv_buf);
                            }

                            if (accum_str_len + to_add.len < 256) {
                                common.copy(eval_buffer[accum_str_len..], to_add);
                                accum_str_len += to_add.len;
                            }
                        } else if (last_op == '=') {
                            if (val.etype == .string) {
                                accum_int = if (common.streq(eval_buffer[0..accum_str_len], val.str_val)) 1 else 0;
                            } else {
                                accum_int = 0;
                            }
                            current_type = .int;
                        } else if (last_op == '!') {
                            if (val.etype == .string) {
                                accum_int = if (!common.streq(eval_buffer[0..accum_str_len], val.str_val)) 1 else 0;
                            } else {
                                accum_int = 1;
                            }
                            current_type = .int;
                        } else {
                            common.printZ("Error: Invalid op for strings\n");
                        }
                    } else {
                        common.printZ("Error: Type mismatch\n");
                    }
                }
            }

            if (pos < expr_in.len) {
                last_op = c;
                if (c == '=' or c == '!') {
                    start = pos + 2;
                    pos += 1;
                } else {
                    start = pos + 1;
                }
            }
        }
        pos += 1;
    }

    if (current_type == .int) {
        return .{ .str_val = "", .int_val = accum_int, .etype = .int };
    } else {
        // Copy the local eval_buffer to the global result buffer so it persists after return
        common.copy(global_result_buffer[0..], eval_buffer[0..accum_str_len]);
        return .{ .str_val = global_result_buffer[0..accum_str_len], .int_val = 0, .etype = .string };
    }
}

// --- commands ---

fn execSetString(buffer: []const u8, stmt: parser.Statement) void {
    const arg = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    if (common.indexOf(arg, '=')) |eq_pos| {
        const name = trim(arg[0..eq_pos]);
        const expr = arg[eq_pos + 1 ..];
        const res = evaluateExpression(expr);
        // Force string
        if (res.etype == .string) {
            setVariable(name, res.str_val, .string, 0);
        } else {
            // Convert int to string if assigning to string? Or error?
            // "set string ... = 10" -> usually error or auto-cast.
            // Let's auto-cast for friendliness
            const s = common.intToString(res.int_val, &int_conv_buf);
            setVariable(name, s, .string, 0);
        }
    }
}

fn execSetInt(buffer: []const u8, stmt: parser.Statement) void {
    const arg = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    if (common.indexOf(arg, '=')) |eq_pos| {
        const name = trim(arg[0..eq_pos]);
        const expr = arg[eq_pos + 1 ..];
        const res = evaluateExpression(expr);
        if (res.etype == .int) {
            setVariable(name, "", .int, res.int_val);
        } else {
            common.printZ("Error: Expected int\n");
        }
    }
}

fn execPrint(buffer: []const u8, stmt: parser.Statement) void {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const res = evaluateExpression(expr);

    if (res.etype == .string) {
        for (res.str_val) |c| {
            common.print_char(c);
        }
    } else {
        const s = common.intToString(res.int_val, &int_conv_buf);
        for (s) |c| {
            common.print_char(c);
        }
    }
    common.print_char('\n');
}

pub fn evaluateCondition(buffer: []const u8, stmt: parser.Statement) bool {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const res = evaluateExpression(expr);
    if (res.etype == .int) {
        return res.int_val != 0;
    }
    return res.str_val.len > 0;
}

fn splitArgs(expr: []const u8) struct { args: [4][]const u8, count: usize } {
    var res: [4][]const u8 = [_][]const u8{""} ** 4;
    var count: usize = 0;
    var start: usize = 0;
    var depth: i32 = 0;
    var in_quotes: bool = false;

    for (expr, 0..) |c, i| {
        if (c == '"') in_quotes = !in_quotes;
        if (in_quotes) continue;

        if (c == '(') depth += 1;
        if (c == ')') depth -= 1;
        if (depth == 0 and c == ',') {
            if (count < 4) {
                res[count] = trim(expr[start..i]);
                count += 1;
                start = i + 1;
            }
        }
    }
    if (count < 4) {
        res[count] = trim(expr[start..]);
        count += 1;
    }
    return .{ .args = res, .count = count };
}

fn getDrive() common.ata.Drive {
    return if (common.global_common.selected_disk == 0) common.ata.Drive.Master else common.ata.Drive.Slave;
}

fn execDelete(buffer: []const u8, stmt: parser.Statement) void {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const res = evaluateExpression(expr);
    if (res.etype != .string) return;

    const drive = getDrive();
    if (common.fat.read_bpb(drive)) |bpb| {
        // Try file first
        if (!common.fat.delete_file(drive, bpb, common.global_common.current_dir_cluster, res.str_val)) {
            // If failed, try directory (recursive delete)
            _ = common.fat.delete_directory(drive, bpb, common.global_common.current_dir_cluster, res.str_val, true);
        }
    }
}

fn execRename(buffer: []const u8, stmt: parser.Statement) void {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const args = splitArgs(expr);
    if (args.count < 2) return;

    const old_path_res = evaluateExpression(args.args[0]);
    const new_path_res = evaluateExpression(args.args[1]);

    if (old_path_res.etype == .string and new_path_res.etype == .string) {
        // Safety copy both paths
        var old_buf: [64]u8 = [_]u8{0} ** 64;
        const old_len = if (old_path_res.str_val.len > 64) 64 else old_path_res.str_val.len;
        common.copy(old_buf[0..], old_path_res.str_val[0..old_len]);
        const old_p = old_buf[0..old_len];

        var new_buf: [64]u8 = [_]u8{0} ** 64;
        const new_len = if (new_path_res.str_val.len > 64) 64 else new_path_res.str_val.len;
        common.copy(new_buf[0..], new_path_res.str_val[0..new_len]);
        const new_p = new_buf[0..new_len];

        const drive = getDrive();
        if (common.fat.read_bpb(drive)) |bpb| {
            _ = common.fat.rename_file(drive, bpb, common.global_common.current_dir_cluster, old_p, new_p);
        }
    }
}

fn execCopy(buffer: []const u8, stmt: parser.Statement) void {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const args = splitArgs(expr);
    if (args.count < 2) return;

    const src_res = evaluateExpression(args.args[0]);
    const dest_res = evaluateExpression(args.args[1]);

    if (src_res.etype == .string and dest_res.etype == .string) {
        // Safety copy paths
        var src_buf: [64]u8 = [_]u8{0} ** 64;
        const src_len = if (src_res.str_val.len > 64) 64 else src_res.str_val.len;
        common.copy(src_buf[0..], src_res.str_val[0..src_len]);
        const src_p = src_buf[0..src_len];

        var dest_buf: [64]u8 = [_]u8{0} ** 64;
        const dest_len = if (dest_res.str_val.len > 64) 64 else dest_res.str_val.len;
        common.copy(dest_buf[0..], dest_res.str_val[0..dest_len]);
        const dest_p = dest_buf[0..dest_len];

        const drive = getDrive();
        if (common.fat.read_bpb(drive)) |bpb| {
            const entry = common.fat.find_entry(drive, bpb, common.global_common.current_dir_cluster, src_p);
            if (entry) |ent| {
                if ((ent.attr & 0x10) != 0) {
                    _ = common.fat.copy_directory(drive, bpb, common.global_common.current_dir_cluster, src_p, dest_p);
                } else {
                    _ = common.fat.copy_file(drive, bpb, common.global_common.current_dir_cluster, src_p, dest_p);
                }
            }
        }
    }
}

fn execMkdir(buffer: []const u8, stmt: parser.Statement) void {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const res = evaluateExpression(expr);
    if (res.etype == .string) {
        const drive = getDrive();
        if (common.fat.read_bpb(drive)) |bpb| {
            _ = common.fat.create_directory(drive, bpb, common.global_common.current_dir_cluster, res.str_val);
        }
    }
}

fn execWriteFile(buffer: []const u8, stmt: parser.Statement) void {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const args = splitArgs(expr);
    if (args.count < 2) return;

    const path_res = evaluateExpression(args.args[0]);
    // Safety copy path
    var path_buf: [64]u8 = [_]u8{0} ** 64;
    const path_len = if (path_res.str_val.len > 64) 64 else path_res.str_val.len;
    common.copy(path_buf[0..], path_res.str_val[0..path_len]);
    const path = path_buf[0..path_len];

    const data_res = evaluateExpression(args.args[1]);

    if (path_res.etype == .string and data_res.etype == .string) {
        const drive = getDrive();
        if (common.fat.read_bpb(drive)) |bpb| {
            _ = common.fat.write_file(drive, bpb, common.global_common.current_dir_cluster, path, data_res.str_val);
        }
    }
}

fn execSleep(buffer: []const u8, stmt: parser.Statement) void {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const res = evaluateExpression(expr);
    if (res.etype == .int) {
        if (res.int_val > 0) {
            common.global_common.sleep(@intCast(res.int_val));
        }
    }
}

fn execCreateFile(buffer: []const u8, stmt: parser.Statement) void {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const res = evaluateExpression(expr);
    if (res.etype == .string) {
        const drive = getDrive();
        if (common.fat.read_bpb(drive)) |bpb| {
            _ = common.fat.write_file(drive, bpb, common.global_common.current_dir_cluster, res.str_val, "");
        }
    }
}

fn execShell(buffer: []const u8, stmt: parser.Statement) void {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const res = evaluateExpression(expr);
    if (res.etype == .string) {
        shell.shell_execute_literal(res.str_val);
    }
}

// Helper for trig: returns sin(deg) * 100
fn approx_sin(deg: i32) i32 {
    var x = @mod(deg, 360);
    if (x < 0) x += 360;

    // Normalize to 0-180
    var sign: i32 = 1;
    if (x > 180) {
        x -= 180;
        sign = -1;
    }

    // 0-180 approximation: 4*x*(180-x) / (40500 - x*(180-x))
    // This is Bhaskara I's sine approximation formula
    // For x in degrees: sin(x) approx 4x(180-x) / (40500 - x(180-x))
    const x_180_x = x * (180 - x);
    const num = 4 * x_180_x;
    const den = 40500 - x_180_x;
    if (den == 0) return 0;
    return @intCast(sign * @divTrunc(num * 100, den));
}

// Execute a parsed statement
pub fn execute(buffer: []const u8, stmt: parser.Statement, exit_flag: *bool) void {
    switch (stmt.cmd_type) {
        .set_string => execSetString(buffer, stmt),
        .set_int => execSetInt(buffer, stmt),
        .print => execPrint(buffer, stmt),
        .fs_delete => execDelete(buffer, stmt),
        .fs_rename => execRename(buffer, stmt),
        .fs_mkdir => execMkdir(buffer, stmt),
        .fs_copy => execCopy(buffer, stmt),
        .fs_write => execWriteFile(buffer, stmt),
        .fs_create => execCreateFile(buffer, stmt),
        .sleep => execSleep(buffer, stmt),
        .shell_exec => execShell(buffer, stmt),
        .reboot => common.reboot(),
        .shutdown => common.shutdown(),
        .exit => exit_flag.* = true,
        .if_stmt, .while_stmt, .else_stmt, .end_block => {
            // These are handled by the interpreter loop
        },
        .unknown => common.printZ("Syntax Error\n"),
        .empty => {},
    }
}
