const common = @import("common.zig");
const smp = @import("../smp.zig");

pub fn execute() void {
    const info = smp.get_cpu_info();

    common.printZ("--- CPU Information ---\n");
    common.printZ("Vendor ID:     ");
    common.printZ(info.vendor[0..12]);
    common.printZ("\n");

    common.printZ("Model Name:    ");
    var len: usize = 0;
    while (len < 48 and info.brand[len] != 0) : (len += 1) {}
    common.printZ(info.brand[0..len]);
    common.printZ("\n");

    common.printZ("Cores Found:   ");
    common.printNum(@intCast(smp.detected_cores));
    common.printZ("\n");

    common.printZ("Cores Online:  ");
    common.printNum(@intCast(smp.get_online_cores()));
    common.printZ("\n");

    common.printZ("Family/Model:  ");
    common.printNum(@intCast(info.family));
    common.printZ("/");
    common.printNum(@intCast(info.model));
    common.printZ(" (Stepping ");
    common.printNum(@intCast(info.stepping));
    common.printZ(")\n");

    // Check for some features (simplified)
    common.printZ("Features:      ");

    var eax: u32 = 1;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax_out] "={eax}" (eax),
          [ebx_out] "={ebx}" (ebx),
          [ecx_out] "={ecx}" (ecx),
          [edx_out] "={edx}" (edx),
        : [eax_in] "{eax}" (eax),
    );

    if ((edx & (1 << 0)) != 0) common.printZ("FPU ");
    if ((edx & (1 << 23)) != 0) common.printZ("MMX ");
    if ((edx & (1 << 25)) != 0) common.printZ("SSE ");
    if ((edx & (1 << 26)) != 0) common.printZ("SSE2 ");
    if ((ecx & (1 << 0)) != 0) common.printZ("SSE3 ");
    if ((ecx & (1 << 28)) != 0) common.printZ("AVX ");

    common.printZ("\n-----------------------\n");
}
