pub const InputEvent = extern struct {
    event_type: u32,
    code: u32,
    value: i32,
    value2: i32,
    value3: i32,
};

const QUEUE_SIZE: usize = 256;

var queue: [QUEUE_SIZE]InputEvent = undefined;
var head: usize = 0;
var tail: usize = 0;

fn save_eflags() u32 {
    var eflags: u32 = undefined;
    asm volatile (
        \\pushfl
        \\popl %[eflags]
        : [eflags] "=r" (eflags),
    );
    return eflags;
}

fn restore_eflags(eflags: u32) void {
    asm volatile (
        \\pushl %[eflags]
        \\popfl
        :
        : [eflags] "r" (eflags),
        : .{ .memory = true });
}

pub fn push(event_type: u32, code: u32, value: i32, value2: i32, value3: i32) void {
    const saved = save_eflags();
    asm volatile ("cli");
    defer restore_eflags(saved);

    const next = (head + 1) & (QUEUE_SIZE - 1);
    if (next == tail) return;
    queue[head] = .{
        .event_type = event_type, .code = code,
        .value = value, .value2 = value2, .value3 = value3,
    };
    head = next;
}

pub fn poll() ?InputEvent {
    if (head == tail) return null;
    const saved = save_eflags();
    asm volatile ("cli");
    defer restore_eflags(saved);

    const ev = queue[tail];
    tail = (tail + 1) & (QUEUE_SIZE - 1);
    return ev;
}
