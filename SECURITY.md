# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark:|

## Reporting a Vulnerability

If you discover a security vulnerability in NovumOS, please report it responsibly.

### How to Report

1. **Do NOT** open a public GitHub Issue
2. Email: minecanton209@gmail.com
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (optional)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 7 days
- **Fix Timeline**: Depends on severity
  - Critical: ASAP (within 30 days)
  - High: Within 90 days
  - Medium: Within 180 days
  - Low: Next release

### Disclosure Policy

- We request a **coordinated disclosure** period
- Public disclosure only after fix is released
- Credit to reporter in release notes (if desired)

## Security Considerations

NovumOS is a learning OS project. It is NOT designed for production use or security-critical environments.

Known limitations:
- No user permission model
- No secure boot
- No encrypted storage
- Limited memory protection

## Security Updates

Security updates will be released via:
- GitHub Releases
- Security Advisories

## Scope

This security policy applies to:
- Kernel code (`*.asm` in root)
- Nova language interpreter
- Bootloader
- SDK

Out of scope:
- Third-party tools (QEMU, NASM, Zig)
- User-provided Nova scripts
- External documentation