# NovumOS SDK

Software Development Kit for creating user-mode applications for NovumOS.

## Quick Start

### Building an Application (Windows)

```batch
cd sdk\examples\hello_world
..\..\build-app.bat main.c hello.elf
```

### Building an Application (Linux)

```bash
cd sdk/examples/hello_world
../../build-app.sh main.c hello.elf
```

## API Reference
 
### System Calls
 
All system calls are exposed through `<novum.h>`. Available functions:
 
#### Process & System
- `void nv_exit(int code)`: Exit the current program.
- `void nv_sleep(uint32_t ms)`: Sleep for N milliseconds.
- `uint32_t nv_get_ticks(void)`: Get system timer ticks since boot.
- `void nv_shutdown(void)`: Power off the system.
- `void nv_reboot(void)`: Reboot the system.
 
#### Console I/O
- `void nv_print(const char* str)`: Print a null-terminated string.
- `char nv_getchar(void)`: Wait for keyboard input.
- `void nv_set_cursor(uint8_t row, uint8_t col)`: Move cursor.
- `void nv_get_cursor(uint8_t* row, uint8_t* col)`: Get cursor position.
- `void nv_clear_screen(void)`: Clear display.
- `void nv_draw_char_at(uint8_t r, uint8_t c, uint8_t ch, uint16_t attr)`: Direct VGA draw.
 
#### Hardware & Time
- `uint8_t nv_inb(uint16_t port)` / `void nv_outb(uint16_t port, uint8_t val)`: I/O Port access.
- `void nv_get_datetime(nv_datetime_t* dt)`: Get RTC time and date.
 
#### Memory Management
- `void* nv_malloc(uint32_t size)`: Allocate heap memory.
- `void nv_free(void* ptr)`: Free heap memory.
- `void nv_mmap_range(uint32_t vaddr, uint32_t size)`: Map virtual memory.
 
#### Utilities
- `int nv_check_ctrl_c(void)`: Check for Ctrl+C interrupt.

## Examples

### Hello World
```c
#include <novum.h>

int main() {
    nv_clear_screen();
    nv_print("Hello from NovumOS!");
    nv_getchar();
    nv_exit(0);
    return 0;
}
```

### Interactive Input
```c
#include <novum.h>

int main() {
    nv_clear_screen();
    nv_print("Press any key...");
    char c = nv_getchar();
    nv_print("You pressed: ");
    // Note: Need to implement char printing
    nv_exit(0);
    return 0;
}
```

## Building libnovum

To rebuild the SDK library:

```batch
cd sdk\libnovum
build.bat
```

This creates `sdk\libnovum.a` which is linked with all applications.

## Project Structure

```
sdk/
├── README.md           # This file
├── libnovum/           # Core library
│   ├── src/
│   │   └── main.zig    # Syscall wrappers
│   ├── include/
│   │   └── novum.h     # C header
│   ├── build.bat       # Build script
│   └── libnovum.a      # Compiled library
├── examples/           # Example applications
│   └── hello_world/
│       └── main.c
├── linker_app.ld       # Linker script for apps
├── build-app.bat       # Helper build script (Windows)
└── build-app.sh        # Helper build script (Linux)
```

## Advanced Topics

### Custom Linker Script
Applications use `sdk/linker_app.ld` which sets up the proper memory layout for user-mode execution.

### Zig Applications
You can also write applications in Zig by importing the SDK:

```zig
const novum = @import("../../libnovum/src/main.zig");

pub fn main() void {
    novum.print("Hello from Zig!");
    novum.exit(0);
}
```

## Troubleshooting

**Q: My app doesn't link**
- Make sure `sdk/libnovum.a` exists (run `sdk/libnovum/build.bat`)
- Check that you're using the correct target: `x86-freestanding`

**Q: Syscalls don't work**
- Ensure you're running on NovumOS (not a regular OS)
- Check that your kernel supports the syscall numbers in use

## License

Same as NovumOS main project.
