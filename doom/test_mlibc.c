#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static void inline_syscall(uint32_t n, uint32_t a1) {
    asm volatile("int $0x80" : : "a"(n), "b"(a1) : "memory");
}

static void putstr(const char *s) {
    uint32_t len = 0;
    while (s[len]) len++;
    asm volatile("int $0x80" : : "a"(103), "b"(1), "c"(s), "d"(len) : "memory");
}

int main(int argc, char **argv, char **envp) {
    putstr("Hello from mlibc!\n");
    putstr("argc="); { char buf[16]; int n=argc,i=0; do { buf[i++]='0'+n%10; n/=10; } while(n); while(i>0) putstr((char[]){buf[--i],0}); putstr("\n"); }
    if (envp && envp[0]) { putstr("envp[0]="); putstr(envp[0]); putstr("\n"); }
    putstr("Testing printf...\n");
    printf("printf works! argc=%d\n", argc);
    putstr("Testing malloc...\n");
    void *p = malloc(640*400*4);
    if (!p) { putstr("malloc FAILED\n"); return 1; }
    putstr("malloc OK: "); { char buf[16]; uint32_t addr=(uint32_t)(uintptr_t)p; const char hex[]="0123456789ABCDEF"; putstr((char[]){'0','x',hex[(addr>>28)&0xF],hex[(addr>>24)&0xF],hex[(addr>>20)&0xF],hex[(addr>>16)&0xF],hex[(addr>>12)&0xF],hex[(addr>>8)&0xF],hex[(addr>>4)&0xF],hex[addr&0xF],0}); putstr("\n"); }
    memset(p, 0xAA, 640*400*4);
    putstr("memset OK\n");
    free(p);
    putstr("free OK\n");
    putstr("Testing clock_gettime...\n");
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    putstr("CLOCK_MONOTONIC: sec="); { char buf[32]; int n=ts.tv_sec,i=0; do { buf[i++]='0'+n%10; n/=10; } while(n); while(i>0) putstr((char[]){buf[--i],0}); putstr(" nsec="); n=ts.tv_nsec; i=0; do { buf[i++]='0'+n%10; n/=10; } while(n); while(i>0) putstr((char[]){buf[--i],0}); putstr("\n"); }
    putstr("All tests passed!\n");
    return 0;
}
