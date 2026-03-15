// NovumOS libc stubs header for C code
#ifndef _NOVUM_LIBC_H
#define _NOVUM_LIBC_H

#include <stddef.h>
#include <stdint.h>

void *memcpy(void *dest, const void *src, size_t n);
void *memset(void *s, int c, size_t n);
void *memmove(void *dest, const void *src, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);
size_t strlen(const char *s);
int strcmp(const char *s1, const char *s2);

void linenoise_write(const char *buf, size_t n);
int linenoise_getch(void);

void ata_read_sector(uint8_t drive, uint32_t lba, uint8_t* buffer);
void ata_write_sector(uint8_t drive, uint32_t lba, const uint8_t* data);

#endif
