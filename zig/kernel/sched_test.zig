const config = @import("../config.zig");
const common = @import("../commands/common.zig");
const scheduler = @import("scheduler.zig");
const timer = @import("../drivers/timer.zig");
const cpu_time = @import("cpu_time.zig");
const user = @import("../arch/mod.zig").user;

// Debug harness for the stride scheduler: two CPU-bound kernel tasks with
// different weights run for the same wall-clock window; each reports its own
// CPU time when it finishes, so the ratio shows whether weights are honored.
// The shell does not wait on them, so the prompt stays responsive.
//
// The shell runs in Ring 3, but creating a task reads CR3, which is privileged.
// spawn() therefore runs in Ring 0 behind syscall SYSCALL_SCHED_TEST.

pub const SYSCALL_SCHED_TEST: u32 = 117;

const DURATION_TICKS: usize = 500;
const TASKS = [_]struct { name: []const u8, weight: u32 }{
    .{ .name = "sched-w1", .weight = 1 },
    .{ .name = "sched-w4", .weight = 4 },
};

var deadline: usize = 0;

fn busy_entry() noreturn {
    while (timer.get_ticks() < deadline) {
        asm volatile ("pause");
    }
    if (scheduler.current_process()) |p| {
        common.printZ("sched-test: ");
        common.printZ(p.name);
        common.printZ(" weight=");
        common.printNum(@as(i32, @intCast(p.priority)));
        common.printZ(" cpu=");
        common.printNum(@as(i32, @intCast(cpu_time.ticksToMs(p.cpu_ticks, timer.TARGET_FREQ))));
        common.printZ(" ms\n");
    }
    scheduler.exit_process();
}

/// Ring 0 only: creates the busy tasks. Returns false if any task could not be created.
pub fn spawn() bool {
    deadline = timer.get_ticks() + DURATION_TICKS;
    for (TASKS) |t| {
        const p = scheduler.create_process(t.name, @intFromPtr(&busy_entry), false) catch return false;
        _ = scheduler.set_priority(p.id, t.weight);
    }
    return true;
}

/// Syscall entry for SYSCALL_SCHED_TEST: regs.eax = 0 on success, 1 on failure.
pub fn sysSpawn(regs: *user.Registers) void {
    regs.eax = if (spawn()) 0 else 1;
}

pub fn run() void {
    if (!config.ENABLE_DEBUG_COMMANDS or !config.ENABLE_STRIDE_SCHEDULER) {
        common.printZ("sched-test: requires ENABLE_DEBUG_COMMANDS and ENABLE_STRIDE_SCHEDULER\n");
        return;
    }

    common.printZ("sched-test: starting 2 busy tasks for 5 s (weights 1 and 4)\n");
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    const status: u32 = if ((cs & 3) == 3) syscallSpawn() else if (spawn()) 0 else 1;
    if (status != 0) {
        common.printZ("sched-test: could not create tasks\n");
    }
}

fn syscallSpawn() u32 {
    var cx: u32 = undefined;
    var dx: u32 = undefined;
    return asm volatile (
        \\pushl $0
        \\pushl $0
        \\pushfl
        \\movl %esp, %ecx
        \\call 1f
        \\1:
        \\popl %edx
        \\sysenter
        : [ret] "={eax}" (-> u32),
          [cx] "={ecx}" (cx),
          [dx] "={edx}" (dx),
        : [sys] "{eax}" (SYSCALL_SCHED_TEST),
    );
}
