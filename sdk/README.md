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

#### `void nv_exit(int code)`
Exit the current program with the given exit code.

#### `void nv_print(const char* str)`
Print a null-terminated string to the console.

#### `char nv_getchar(void)`
Wait for and return a single character from keyboard input.

#### `void nv_set_cursor(uint8_t row, uint8_t col)`
Set the cursor position on screen (0-indexed).

#### `void nv_get_cursor(uint8_t* row, uint8_t* col)`
Get the current cursor position.

#### `void nv_clear_screen(void)`
Clear the screen and reset cursor to (0,0).

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
