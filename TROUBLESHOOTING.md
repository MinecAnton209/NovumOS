# Troubleshooting

Common issues when building and running NovumOS.

## Build Issues

### "NASM: command not found"

**Solution:** Add NASM to PATH.

Windows:
```powershell
$env:PATH += ";C:\Program Files\NASM"
```

Linux:
```bash
export PATH=$PATH:/usr/bin/nasm
```

### "zig: command not found"

**Solution:** Install Zig.

Windows:
```powershell
winget install zig.zig
```

Linux/macOS:
```bash
brew install zig  # macOS
sudo apt install zig  # Linux
```

Or download from https://ziglang.org/

### Build fails with "invalid instruction"

**Cause:** Zig version too old.

**Solution:** Use Zig master (0.12+):
```bash
# Windows
choco install zig --version=latest
# or download from ziglang.org
```

### "cannot find linker.ld"

**Cause:** Running build from wrong directory.

**Solution:**
```bash
cd E:\NewOS
.\build.bat
```

---

## QEMU Issues

### "QEMU: boot failure"

**Causes:**
1. No disk image
2. Corrupted image
3. Wrong QEMU settings

**Solutions:**
- Regenerate image: `.\build.bat`
- Try different QEMU version
- Check disk geometry in VM settings

### "KVM: acceleration not available"

**Cause:** Virtualization not enabled.

**Solution:**

**Windows:**
1. Enable Hyper-V in Windows Features
2. Or use `-accel tcg` flag:
```bash
qemu-system-i386 -cdrom NovumOS.iso -accel tcg
```

**Linux:**
```bash
sudo modprobe kvm
sudo modprobe kvm_intel  # for Intel CPUs
```

### "Display window not opening"

**Cause:** Display/GUI not configured.

**Solutions:**
- Use `-nographic` for serial console:
```bash
qemu-system-i386 -cdrom NovumOS.iso -nographic
```
- Install GUI (GTK/SDL):
```bash
# Linux
sudo apt install libsdl2-2.0-0

# macOS
brew install sdl2
```

### "Network not working"

**Cause:** QEMU network not configured.

**Solution:** Use user mode networking:
```bash
qemu-system-i386 -cdrom NovumOS.iso -net nic -net user
```

### "Serial port not working"

**Cause:** Serial redirect not set.

**Solution:**
```bash
# Via virtual serial
qemu-system-i386 -cdrom NovumOS.iso -serial stdio

# Via TCP
qemu-system-i386 -cdrom NovumOS.iso -serial telnet:127.0.0.1:4444,server,nowait
# Connect: nc 127.0.0.1 4444
```

---

## Runtime Issues

### Kernel Panic: "Page Fault"

**Cause:** Memory access violation.

**Solution:**
1. Check memory allocation code
2. Enable debug in QEMU:
```bash
qemu-system-i386 -cdrom NovumOS.iso -d int
```

### Kernel Panic: "Double Fault"

**Cause:** Exception during exception handler.

**Common causes:**
- Stack overflow
- Invalid IDT entry
- Missing GDT setup

### Black screen after boot

**Solutions:**
1. Try different resolution: `res 800 600`
2. Use serial console to debug:
```bash
qemu-system-i386 -cdrom NovumOS.iso -nographic
```
3. Check QEMU log: `-d debug`

### Keyboard not responding

**Cause:** PS/2 keyboard driver issue.

**Solutions:**
1. Click on QEMU window first
2. Try: `setkeycodes`
3. Restart QEMU

---

## Performance Issues

### Slow execution

**Solutions:**
- Enable KVM: `-enable-kvm` (Linux)
- Use host CPU: `-cpu host`
- Allocate more RAM: `-m 256`

### High memory usage

**Cause:** Memory leak or large heap.

**Solution:** Check `[mem]` command in OS.

---

## Platform-Specific

### macOS ARM (Apple Silicon)

**Issue:** QEMU may be slow.

**Solution:**
```bash
# Use x86_64 QEMU via Rosetta
arch -x86_64 qemu-system-i386 ...
```

### WSL2

**Issue:** GPU passthrough issues.

**Solution:**
```bash
qemu-system-i386 -cdrom NovumOS.iso -vga std -accel tcg
```

### VirtualBox

**Issue:** Nested virtualization conflict.

**Solution:** Disable nested virtualization or use Physical hardware.

---

## Getting Help

1. Check [GitHub Issues](https://github.com/MinecAnton209/NovumOS/issues)
2. Search [Discussions](https://github.com/MinecAnton209/NovumOS/discussions)
3. Open new Issue with:
   - OS version
   - QEMU version
   - Steps to reproduce
   - Screenshots/logs

## Reporting Bugs

When reporting, include:

```markdown
### Environment
- OS: Windows 11 / Ubuntu 22.04 / macOS 14
- QEMU: version 8.x
- Zig: version 0.x.x
- NASM: version 2.x.x

### Steps to Reproduce
1. Run build
2. Run qemu-system-i386 -cdrom NovumOS.iso
3. Type "res 800 600"

### Expected Behavior
Resolution changes to 800x600

### Actual Behavior
Kernel panic: page fault

### Logs
[Add QEMU output or screenshot]
```