# Nova Language Guide

Nova is a statement-based interpreted language for the NovumOS kernel. It provides a simple environment for automation, system control, and filesystem management, featuring floating-point support, modular sub-systems, and a robust REPL.

---

## ⚡ Quick Rules (v0.22+)
- **Semicolons are Mandatory**: Every statement must end with a `;` (e.g., `print("hi");`).
- **Modular Access**: Standard functions like `sin` or `delay` are now in modules (`math`, `sys`) and require an `import`.
- **Case Sensitivity**: Keywords (`if`, `while`, `set`) are lowercase.

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

### System & Hardware (Module `sys`)
*Requires `import "sys"`*

| Function | Description | Example |
|----------|-------------|---------|
| `sys.get_mem()` | Returns current free memory (bytes) | `set m = sys.get_mem();` |
| `sys.get_temp()` | Returns CPU temp in Celsius | `print(sys.get_temp());` |
| `sys.delay(ms)` | Wait for N milliseconds | `sys.delay(1000);` |
| `sys.shell(cmd)` | Execute kernel shell command | `sys.shell("ls /bin");` |
| `sys.color(f, b)`| Set VGA colors (0-15) | `sys.color(12, 0);` |
| `sys.key()` | Returns raw keyboard scancode | `set k = sys.key();` |
| `sys.exec(cmd)` | Alias for shell command | `sys.exec("reboot");` |
| `sys.reboot()` | Reboots the system | `sys.reboot();` |
| `sys.shutdown()` | Shuts down the system | `sys.shutdown();` |
| `exit()` | Terminate script or REPL (Global) | `exit();` |

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

### Math & Trigonometry (Module `math`)
*Requires `import "math"`*

| Function | Description | Example / Note |
|----------|-------------|----------------|
| `math.abs(n)` | Absolute value | `math.abs(-5); // 5` |
| `math.min(a, b)`| Minimum of two values | `math.min(10, 20); // 10` |
| `math.max(a, b)`| Maximum of two values | `math.max(-1, 5); // 5` |
| `math.random(l, h)`| Pseudo-random integer | `math.random(1, 100);` |
| `math.sin(v)` | Sine (Float) | Precision: Bhaskara I |
| `math.cos(v)` | Cosine (Float) | Respects `math.set_angles` |
| `math.set_angles(m)`| Set mode: `rad` or `deg` | `math.set_angles("rad");` |
| `math.rad(deg)` | Degrees to Radians | `math.rad(180); // 3.141...` |
| `math.deg(rad)` | Radians to Degrees | `math.deg(3.141); // 180.0` |

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
2. Search system directory: `/.SYSTEM/NOVA/MOD/`.

```nova
import "math";
import "/lib/utils.nv";
```

*Note: Autocompletion (Tab) for module functions only becomes active after the module is successfully imported.*

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

## 📝 5. Comments & Formatting
Nova supports single-line (`//`) and multi-line (`/* ... */`) comments.

### ⌨️ Multi-line REPL
The Nova REPL supports multi-line input. If a statement is not terminated with a `;` or a closing brace `}`, the REPL will switch to continuation mode (`...` prompt):
```nova
nova> print("Hello " +
 ...  "World");
Hello World
```

---

---

## 🎨 6. VGA Color Guide

The `sys.color(fg, bg)` function uses standard 16-color VGA palette indices (0-15).

| ID | Color | ID | Color |
|----|-------|----|-------|
| **0** | Black | **8** | Dark Gray |
| **1** | Blue | **9** | Light Blue |
| **2** | Green | **10** | Light Green |
| **3** | Cyan | **11** | Light Cyan |
| **4** | Red | **12** | Light Red |
| **5** | Magenta | **13** | Light Magenta (Pink) |
| **6** | Brown | **14** | Yellow |
| **7** | Light Gray | **15** | White |

### Example: Yellow on Blue
```nova
import "sys"
sys.color(14, 1);
print("Warning: System Overload");
```

---

## 💻 7. Technical Specifications
- **Execution**: Recursive block-based interpreter with dynamic heap allocation.
- **Math Engine**: High-speed fixed-approximation trigonometry optimized for x86 kernel space.
- **FS Support**: Full integration with NovumOS FAT driver (v0.22.0).
- **Interface**: Enhanced REPL with module-aware tab completion and history (20 entries).
