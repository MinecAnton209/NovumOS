# NovumOS Commands Reference (v0.19)

Comprehensive documentation for all built-in NovumOS shell commands.

---

## 🚀 Quick Reference Table

| Command | Description | Usage |
|---------|-------------|-------|
| `help` | Show command list | `help [page]` |
| `docs` | Detailed documentation | `docs [topic]` |
| `ls` | List files/folders | `ls [path]` |
| `pwd` | Print working directory | `pwd` |
| `cd` | Change directory | `cd <path>` |
| `mkdir` | Create directory | `mkdir <name>` |
| `touch` | Create empty file | `touch <path>` |
| `edit` | Text editor | `edit <path>` |
| `write` | Write/Append text to file | `write [-a] <path> <text>` |
| `cat` | View file content (Raw) | `cat <path>` |
| `more` | Paginated file viewer | `more <file>` |
| `rm` | Delete file/dir | `rm [-d] [-r] <f|*>` |
| `cp` | Copy file/folder | `cp <src> <dest>` |
| `mv` | Move/Rename file/dir | `mv <src> <dest>` |
| `tree` | Directory tree | `tree` |
| `sysinfo` | System info & RAM detection | `sysinfo` |
| `uptime` | System uptime | `uptime` |
| `mem` | Memory status & Stress Tool | `mem [--test]` |
| `nova` | Nova Interpreter | `nova` |
| `reboot` | Restart system | `reboot` |
| `shutdown` | Power off | `shutdown` |

---

## 🛠 System Control

### `help`
Displays a list of available commands.
- **Usage:** `help [page]`

### `docs`
Displays detailed help topics.
- **Usage:** `docs [topic]`
- **Topics:** `nova`, `memory`.

### `clear`
Clears the console screen and resets the cursor position to the top-left.
- **Usage:** `clear`

### `about`
Displays legal information, versioning details, and the creator credits.
- **Usage:** `about`

### `sysinfo`
Displays hardware information, CPU details, and **detected physical RAM**.
- **Usage:** `sysinfo`
- **Dynamic:** Reports exact memory provided by the BIOS (CMOS).

### `uptime`
Shows how long the system has been running since the last boot.
- **Usage:** `uptime`

### `time`
Displays the current Real-Time Clock (RTC) date and time.
- **Usage:** `time`

### `reboot`
Safely restarts the computer using the keyboard controller pulse.
- **Usage:** `reboot`

### `shutdown`
Powers off the system using ACPI commands.
- **Usage:** `shutdown`

---

## 📁 File System Navigation

### `ls`
Lists files and directories in the target path or current directory.
- **Usage:** `ls [path]`
- **Flags:**
  - `-l`: Detailed view (if supported)
  - `-a`: Show hidden files
- **Examples:**
  - `ls` (Current directory)
  - `ls 123/` (Contents of folder '123')
  - `ls /` (Root directory)

### `pwd`
Prints the absolute path of the current working directory.
- **Usage:** `pwd`

### `cd`
Changes the current working directory.
- **Usage:** `cd <path>`
- **Features:**
  - Supports absolute paths (starting with `/`) and relative paths.
  - Supports quoted strings for directory names with spaces (e.g., `cd "New Folder"`).
- **Navigation:**
  - `cd folder` - Enter a directory.
  - `cd ..` - Go to the parent directory.
  - `cd /` - Return to the root directory.
- **Easter Eggs:**
  - Try `cd .` or `cd ..` while already in the root!

### `lsdsk`
Lists all detected storage devices (Master/Slave) and their capacity.
- **Usage:** `lsdsk`

### `mount`
Selects which disk drive is currently active for file operations.
- **Usage:** `mount <0|1>`
- **0:** Master Drive
- **1:** Slave Drive

### `mkdir` (alias: `md`)
Creates a new directory in the current path.
- **Usage:** `mkdir <name>`
- **Example:** `mkdir documents`

### `tree`
Visualizes the entire directory structure starting from the current location.
- **Usage:** `tree`

---

## 📄 File Manipulation

### `touch`
Creates a new empty file at the specified path.
- **Usage:** `touch <file_path>`
- **Example:** `touch logs/boot.log`

### `write`
Writes or appends a string of text into a file.
- **Usage:** `write [-a] <file_path> <text>`
- **Options:**
  - `-a`: Append mode. Adds text to the end of the file instead of overwriting.
- **Note:** Overwriting an existing file without `-a` will show a warning.
- **Example:** `write -a logs.txt "New entry"`

### `cat`
Displays the raw content of a file. Use `more` for larger files.
- **Usage:** `cat <file_path>`

### `more`
Paginated file viewer with scrolling support. 
- **Usage:** `more [options] <file_path>`
- **Controls:** 
  - **Arrows**: Scroll line by line
  - **Space/PgDn**: Scroll page
  - **Q**: Quit
  - **G**: Jump to end
- **Piping:** Can be used at the end of a pipe (e.g., `ls | more`).
- **Features:** Supports line wrapping (79 cols) and logical line numbering (`-n`).

### `rm`
Deletes files or directories.
- **Usage:** `rm [-d] [-r] <file|*>`
- **Flags:**
  - `-d`: Required to delete a directory. It must be empty.
  - `-r`: Recursive. Deletes a directory and everything inside it.
- **Wildcards:**
  - `rm *` is a protected operation. 
  - To wipe a folder completely, you **must** use: `rm -dr * --yes-i-am-sure`

### `cp`
Copies a file or an entire directory (recursively) from one path to another.
- **Usage:** `cp <src> <dest>`
- **Note:** No flags required for recursive copy; it is automatic for directories.

### `mv` (alias: `ren`)
Moves or renames a file or directory.
- **Usage:** `mv <src> <dest>`
- **Example:** `ren old_folder new_folder`

---

## 🔧 Tools & Utilities

### `edit`
Starts the primitive text editor to create or modify text files.
- **Usage:** `edit <file_path>`

### `nova`
Launches the Nova Scripting Interpreter for running scripts.
- **Usage:** `nova`

### `mem`
Displays the current status of the System Heap and memory allocator.
- **Usage:** `mem [--test [MB]]`
- **Features:**
  - **Memory Test:** `mem --test 100` allocates and fills 100MB of RAM.
  - **Performance:** Uses **PSE (4MB Huge Pages)** and **Pre-mapping** for maximum speed.
  - **Interruptible:** Press **Ctrl+C** at any time to abort the test.
  - **Garbage Collection:** Automatically triggers a heap cleanup after the test completes or is aborted.

### `history`
Lists the most recently executed commands.
- **Usage:** `history`

### `echo`
Prints the provided text back to the console.
- **Usage:** `echo <text>`

---

## 📀 Formatting

### `format`
Performs a low-level format of the selected drive.
- **Usage:** `format <drive>`
- **WARNING:** Irreversible data loss.

### `mkfs`
Creates a FAT filesystem on the target drive.
- **Usage:** `mkfs-fat16 0` (Formats Master as FAT16)

---
## 🔄 Redirection & Piping
NovumOS shell supports standard output redirection and inter-process piping.

### Output Redirection
Redirects command output to a file on disk.
- **Syntax:** 
  - `command > filename`: Overwrites the target file.
  - `command >> filename`: Appends to the target file.
- **Example:** `ls >> files.txt`

### Piping
Passes the output of one command as input to another.
- **Syntax:** `command1 | command2`
- **Example:** 
  - `ls | more` - View file list with scrolling
  - `cat config.txt | echo` - Pass file content to echo
