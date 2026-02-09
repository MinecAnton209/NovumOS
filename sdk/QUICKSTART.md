# NovumOS SDK Quick Reference

## Building Applications

### Windows
```batch
cd sdk
build-app.bat examples\hello_world\main.c examples\hello_world\hello.elf
```

### Linux
```bash
cd sdk
./build-app.sh examples/hello_world/main.c examples/hello_world/hello.elf
```

## API Cheat Sheet

```c
#include <novum.h>

// Program control
void nv_exit(int code);              // Exit with code

// Console output
void nv_print(const char* str);      // Print string
void nv_clear_screen(void);          // Clear screen

// Cursor control
void nv_set_cursor(uint8_t row, uint8_t col);  // Set position
void nv_get_cursor(uint8_t* row, uint8_t* col); // Get position

// Input
char nv_getchar(void);               // Wait for key
```

## Example: Hello World

```c
#include <novum.h>

int main() {
    nv_clear_screen();
    nv_set_cursor(10, 30);
    nv_print("Hello from NovumOS!");
    nv_getchar();
    nv_exit(0);
    return 0;
}
```

## Directory Structure

```
sdk/
├── libnovum/           # Core library
│   ├── src/main.zig    # Implementation
│   ├── include/novum.h # C header
│   └── build.bat       # Build library
├── examples/           # Sample apps
│   ├── hello_world/
│   └── calculator/
├── build-app.bat       # Build helper (Windows)
├── build-app.sh        # Build helper (Linux)
└── linker_app.ld       # Linker script
```

## Rebuilding libnovum

If you modify the SDK library:

```batch
cd sdk\libnovum
build.bat
```

This creates `sdk/libnovum.a` used by all applications.

## Tips

- All apps must have a `main()` function
- Use `nv_exit(0)` to properly terminate
- Strings must be null-terminated
- Target is always `x86-freestanding`
