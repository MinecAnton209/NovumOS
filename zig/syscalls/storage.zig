// zig/syscalls/storage.zig
// Storage syscalls: ATA_IDENTIFY / READ_SECTOR / WRITE_SECTOR (privileged, deprecated).
//
// These syscalls allow ELFs to talk directly to the disk, bypassing
// simplefs and the file permission layer. They are PRIVILEGED — only
// the shell (and other trusted ELFs) can use them.
//
// For user ELFs, prefer the FAT-based file syscalls (45-52) added in
// Phase 2. These ATA syscalls remain for backward compatibility and
// for shell-internal disk operations.

const common = @import("../commands/common.zig");
const user = @import("../user.zig");
const ata = @import("../drivers/ata.zig");
const logger = @import("../logger.zig");
const syscalls = @import("mod.zig");

/// Syscall 20: ATA_IDENTIFY(EBX = drive) -> EAX
pub fn ataIdentify(regs: *user.Registers) void {
    if (!user.checkPrivilege(regs, "ATA Identify")) return;
    const drive: ata.Drive = @enumFromInt(@as(u1, @intCast(regs.ebx & 1)));
    regs.eax = ata.identify(drive);
}

/// Syscall 21: ATA_READ_SECTOR(EBX = drive, ECX = lba, EDX = buf)
pub fn ataReadSector(regs: *user.Registers) void {
    if (!user.checkPrivilege(regs, "ATA Read Sector")) return;
    const drive: ata.Drive = @enumFromInt(@as(u1, @intCast(regs.ebx & 1)));
    const lba: u32 = regs.ecx;
    if (syscalls.is_safe_user_range(regs.edx, 512)) {
        const ptr = @as([*]u8, @ptrFromInt(regs.edx));
        ata.read_sector(drive, lba, ptr);
    } else {
        logger.security("Invalid buffer pointer for ATA Read");
    }
}

/// Syscall 22: ATA_WRITE_SECTOR(EBX = drive, ECX = lba, EDX = data)
pub fn ataWriteSector(regs: *user.Registers) void {
    if (!user.checkPrivilege(regs, "ATA Write Sector")) return;
    const drive: ata.Drive = @enumFromInt(@as(u1, @intCast(regs.ebx & 1)));
    const lba: u32 = regs.ecx;
    if (syscalls.is_safe_user_range(regs.edx, 512)) {
        const ptr = @as([*]const u8, @ptrFromInt(regs.edx));
        ata.write_sector(drive, lba, ptr);
    } else {
        logger.security("Invalid data pointer for ATA Write");
    }
}
