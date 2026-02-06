# Nova Language - Comprehensive Guide (v0.10.5)

Nova is a statement-based interpreted language for the NovumOS kernel. It provides a simple environment for automation, system control, and filesystem management.

---

## 🚀 1. Variable Management

Nova uses the `set` keyword to declare or update variables.

### Integer Variables (`int`)
32-bit signed values.
```nova
set int age = 20;
set int next = age + 1;
print(next); // 21
```

### String Variables (`string`)
UTF-8 text strings (up to 64 chars).
```nova
set string user = "Admin";
print("User: " + user); // User: Admin
```

---

## 🧮 2. Expressions & Comparisons

### Arithmetic
- `+`, `-`, `*`, `/`
- Use `(...)` for order of operations.

### Comparisons (v0.10+)
Comparison operators return `1` (True) or `0` (False).
- `==` - Equal
- `!=` - Not Equal
- `<` - Less Than
- `>` - Greater Than

### Math Functions (v0.10.2+)
| Function | Description | Note |
|----------|-------------|------|
| `abs(n)` | Absolute value | |
| `min(a, b)`| Minimum of two values | |
| `max(a, b)`| Maximum of two values | |
| `random(min, max)` | Pseudo-random integer | Precision high (TSC seeded) |
| `sin(deg)` | Sine of angle | Returns value * 100 |
| `cos(deg)` | Cosine of angle | Returns value * 100 |
| `tg(deg)`  | Tangent of angle | Same as `tan()` (*100) |
| `ctg(deg)` | Cotangent of angle | Returns value * 100 |

### User Dialogue (v0.10.1+)
```nova
set string name = input("What is your name? ");
print("Hello, " + name + "!");

set int age = input("How old are you? ");
if age > 18 {
    print("Welcome, adult!");
}
```

---

## 📂 3. Filesystem Native Functions

Nova can now manipulate the NovumOS filesystem directly using built-in functions.

| Function | Description | Example |
|----------|-------------|---------|
| `create_file(path)` | Create an empty file | `create_file("test.txt");` |
| `write_file(path, data)` | Write text to file | `write_file("log.txt", "Entry 1");` |
| `mkdir(path)` | Create a directory | `mkdir("scripts");` |
| `delete(path)` | Delete file or directory | `delete("temp.txt");` |
| `rename(old, new)` | Rename/Move file or dir | `rename("a.txt", "b.txt");` |
| `copy(src, dest)` | Copy file or directory | `copy("a.txt", "backup.txt");` |
| `read(path)` | Read file into string | `set string s = read("a.txt");` |

### System Integration (v0.10.2+)
You can now execute shell commands directly from Nova scripts:
- `shell("command")`
- **Example:** `shell("ls /");` or `shell("clear");`

---

## 🚦 4. Control Flow (Blocks)

Nova v0.10 introduces block-based control flow using `{` and `}`.

### If Statements
```nova
set int x = 10;
if x > 5 {
    print("Greater than 5");
} else {
    print("5 or less");
}
```

### While Loops
```nova
set int count = 0;
while count < 3 {
    print("Line " + count);
    set int count = count + 1;
}
```

---

## 📜 5. Script Support (`.nv` files)

You can write Nova scripts in any text editor (like `edit`) and save them with the `.nv` extension.

### Running a script:
From the NovumOS shell:
```bash
1:/> nova myscript.nv
```

---

## 🔧 6. Technical Limits
- **Execution**: Recursive block-based interpreter.
- **Max Variables**: 16.
- **Max String Length**: 64 chars.
- **Max Script Size**: 4096 bytes.
- **Case Sensitivity**: Commands and keywords are case-sensitive (e.g., `if`, not `IF`).

*Generated for NovumOS v0.10*
