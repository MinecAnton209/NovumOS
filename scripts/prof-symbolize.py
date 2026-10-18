#!/usr/bin/env python3
"""Map `prof report` kernel addresses to function names.

Usage: prof-symbolize.py <kernel.elf> [report.txt]

Reads the report from the file argument or stdin (e.g. the serial log captured
with `qemu-system-i386 -serial file:serial.log`). Kernel addresses are resolved
against the symbol table of the ELF with `nm`; user-mode addresses belong to
Ring 3 programs and are printed unchanged.
"""

import bisect
import re
import subprocess
import sys

HOT_LINE = re.compile(r"^\s+(0x[0-9a-fA-F]+)\s+(\d+)\s+(\d+)%")
SECTION = re.compile(r"^(Kernel|User) hot addresses:")
FUNC_TYPES = frozenset("tTwW")


def load_symbols(elf_path):
    out = subprocess.run(
        ["nm", "-n", "--defined-only", elf_path],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    addrs = []
    names = []
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) != 3 or parts[1] not in FUNC_TYPES:
            continue
        addrs.append(int(parts[0], 16))
        names.append(parts[2])
    return addrs, names


def resolve(addr, addrs, names):
    idx = bisect.bisect_right(addrs, addr) - 1
    if idx < 0:
        return "?"
    offset = addr - addrs[idx]
    return f"{names[idx]}+0x{offset:x}"


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    addrs, names = load_symbols(argv[1])
    source = open(argv[2], encoding="utf-8", errors="replace") if len(argv) > 2 else sys.stdin

    section = None
    for line in source:
        header = SECTION.match(line)
        if header:
            section = header.group(1)
            print(line.rstrip())
            continue

        hot = HOT_LINE.match(line)
        if hot and section == "Kernel":
            addr = int(hot.group(1), 16)
            print(f"  {resolve(addr, addrs, names):<40} {hot.group(2):>8} {hot.group(3):>3}%")
        else:
            print(line.rstrip())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
