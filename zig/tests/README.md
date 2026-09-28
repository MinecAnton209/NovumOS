# Host Tests for Nova OS

Tests run on the host (Windows/Linux/macOS) rather than the kernel freestanding environment.
They cover pure logic that doesn't need kernel hardware abstractions.

## Available test steps

Run via `zig build`:

| Step                   | File(s) Tested              | Description                              |
|------------------------|-----------------------------|------------------------------------------|
| `zig build test-str`   | `zig/kernel/str.zig`        | String utility functions                 |
| `zig build test-hash-table` | `zig/nova_legacy/hash_table.zig` | HashTable operations + djb2 hashing |
| `zig build test-common` | `zig/commands/common.zig`   | parse_int, intToString, trim, fmt_to_buf, parseArgs |
| `zig build test-lexer`  | `zig/nova_legacy/lexer.zig` | Tokenized (ported logic)                 |
| `zig build test-parser` | `zig/nova_legacy/parser.zig` | Statement parsing (ported logic)         |
| `zig build test-path-policy` | `zig/kernel/path_policy.zig` | Path canonicalization, blocked paths |
| `zig build test-cfg-write` | `zig/tools/cfg_write.zig`   | Config merge logic                       |
| `zig build test`        | All of the above           | Combined test target                     |

## Approach

### Port-based tests (str, hash_table, common, lexer, parser)
These modules have kernel/freestanding dependencies (`user_malloc`, `common.zig`, `config.zig`). Instead of stubbing the entire kernel, the tests re-implement the pure logic in a host-compatible way.

### Module-level tests (path_policy)
The kernel module `path_policy.zig` is tested in-place by creating a build module with stub dependencies. `build.zig` uses `Module.imports` to redirect the path-based `@import` calls in `path_policy.zig` to stub files in `zig/tests/stubs/`.

### Existing module tests (cfg_write)
`cfg_write.zig` was already testable because it only uses `@import("std")` and a build-system-injected `config_schema` module.

## Adding new tests

1. **For new pure functions:** Add the function and its tests to a port file in `zig/tests/`.
2. **For kernel modules with minimal deps:** Create a module in `build.zig` with `imports` mapping to stub files.
3. **For modules that only need std:** Test in-place with `addAnonymousImport` for external deps.
