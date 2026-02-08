# Nova Language - Comprehensive Guide (v0.21.0)

Nova is a statement-based interpreted language for the NovumOS kernel. It provides a simple environment for automation, system control, and filesystem management, now featuring full floating-point support.

---

## 🚀 1. Variable Management

Nova uses the `set` keyword or direct assignment. Typing is dynamic, but you can use optional type hints for code clarity.

### Types
- **Integer (`int`)**: 32-bit signed values (e.g. `42`, `-10`).
- **Float (`float`)**: 32-bit floating point numbers (e.g. `3.141`, `-0.5`).
- **String (`string`)**: UTF-8 text strings (e.g. `"Hello Nova"`).

### Examples
```nova
set int x = 10;
set float pi = 3.14159;
set string msg = "System Ready";

y = x * 2.5; // Result will be float
```

### Smart String Concatenation
Nova supports automatic type conversion during concatenation using the `+` operator.
```nova
set int temp = 45;
print("Temperature: " + temp + " C"); // "Temperature: 45 C"
set float ftemp = 36.6;
print("Precise: " + ftemp);           // "Precise: 36.600"
```

---

## 🔧 2. Built-in Functions

### System & Hardware
| Function | Description | Example |
|----------|-------------|---------|
| `get_mem()` | Returns current free memory (bytes) | `set m = get_mem();` |
| `get_cpu_temp()` | Returns CPU temp in Celsius | `print(get_cpu_temp());` |
| `delay(ms)` | Wait for N milliseconds | `delay(1000);` |
| `shell(cmd)` | Execute kernel shell command | `shell("ls /bin");` |
| `set_color(f, b)`| Set VGA colors (0-15) | `set_color(12, 0);` |
| `get_key()` | Returns raw keyboard scancode | `set k = get_key();` |
| `exec(cmd)` | Alias for shell command | `exec("reboot");` |
| `exit()` | Terminate script or REPL | `exit();` |

### Filesystem
| Function | Description | Example |
|----------|-------------|---------|
| `read(path)` | Read file into a string | `set s = read("file.txt");` |
| `write(path, d)`| Write/Overwrite file with data | `write("log.nv", "Data");` |
| `create_file(p)`| Create a new empty file | `create_file("test.txt");`|
| `exists(path)` | Returns 1 if file/dir exists | `if exists("sys") { ... }` |
| `mkdir(path)` | Create a new directory | `mkdir("/sys/data");` |
| `size(path)` | Returns file size in bytes | `set s = size("kernel.bin");`|
| `delete(path)` | Remove file or directory | `delete("tmp.txt");` |
| `rename(o, n)` | Rename or move file | `rename("a.txt", "b.txt");`|
| `copy(s, d)` | Copy file to destination | `copy("a.txt", "b.txt");` |

### Math & Trigonometry (v0.21.0+)
| Function | Description | Example / Note |
|----------|-------------|----------------|
| `abs(n)` | Absolute value | `abs(-5); // 5` |
| `min(a, b)`| Minimum of two values | `min(10, 20); // 10` |
| `max(a, b)`| Maximum of two values | `max(-1, 5); // 5` |
| `random(l, h)`| Pseudo-random integer | `random(1, 100);` |
| `sin(v)` | Sine (Float) | Precision: Bhaskara I |
| `cos(v)` | Cosine (Float) | Respects `set_angles` |
| `set_angles(m)`| Set mode: `rad` or `deg` | `set_angles(rad);` |
| `rad(deg)` | Degrees to Radians | `rad(180); // 3.141...` |
| `deg(rad)` | Radians to Degrees | `deg(3.141); // 180.0` |

### String & Data Processing
| Function | Description | Example |
|----------|-------------|---------|
| `len(str)` | Returns string length | `len("Hello"); // 5` |
| `split(s, d, i)`| Get Nth part of split string | `split("a:b:c", ":", 1); // "b"`|
| `int(str)` | Parse string to integer | `int("123");` |
| `str(v)` | Convert value to string | `str(3.14); // "3.140"` |
| `format(v, f)` | Formatter (hex, size, str) | `format(1024, "size"); // "1 KB"`|
| `convert(v, f, t)`| Memory unit converter | `convert(1, "GB", "MB"); // 1024`|

### I/O & Arguments
| Function | Description | Example |
|----------|-------------|---------|
| `input(prompt)` | Prompt user for input (blocking) | `set s = input("Name: ");` |
| `argc()` | Number of script arguments | `print(argc());` |
| `args(index)` | Get Nth argument | `print(args(0));` |

---

## 🏗 3. Module System

Nova supports loading external modules using the `import` keyword.

### Resolution Order:
1. Search local directory of the script.
2. Search system directory: `/.SYSTEM/NOVA/MODULES/`.

```nova
import "math"
import "/lib/utils.nv"
```

---

## 🧊 4. Control Flow

### If / Else
```nova
if x > 10 {
    print("Large");
} else {
    print("Small");
}
```

### While Loops
```nova
set i = 0;
while i < 10 {
    i = i + 1;
    if i == 5 { continue; }
    if i == 8 { break; }
    print(i);
}
```

---

## 📝 5. Comments
Nova supports single-line (`//`) and multi-line (`/* ... */`) comments.

---

## 💻 6. Technical Specifications
- **Execution**: Recursive block-based interpreter with dynamic heap allocation.
- **Math Engine**: High-speed fixed-approximation trigonometry optimized for x86 kernel space.
- **FS Support**: Full integration with NovumOS FAT driver (v0.21.0).

*Documentation generated for NovumOS v0.21.0*
