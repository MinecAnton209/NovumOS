#include <novum.h>
#include <stdint.h>

void print_hex(uint32_t val) {
    char buf[11];
    const char* hex = "0123456789ABCDEF";
    buf[0] = '0';
    buf[1] = 'x';
    for(int i = 0; i < 8; i++) {
        buf[9-i] = hex[val & 0xF];
        val >>= 4;
    }
    buf[10] = '\0';
    nv_print(buf);
}

int main() {
    nv_clear_screen();
    nv_print("NovumOS SDK System Test\n");
    nv_print("-----------------------\n\n");

    // RTC Test
    nv_datetime_t dt;
    nv_get_datetime(&dt);
    nv_print("System Time: ");
    
    // Simplistic number printing
    char nbuf[5];
    nbuf[4] = 0;
    
    print_hex(dt.hour);
    nv_print(":");
    print_hex(dt.minute);
    nv_print(":");
    print_hex(dt.second);
    nv_print(" (UTC)\n");
    
    nv_print("Date: ");
    print_hex(dt.day);
    nv_print("/");
    print_hex(dt.month);
    nv_print("/");
    print_hex(dt.year);
    nv_print("\n");

    // Timer Test
    uint32_t t1 = nv_get_ticks();
    nv_print("Sleeping for 100ms...\n");
    nv_sleep(100);
    uint32_t t2 = nv_get_ticks();
    nv_print("Ticks elapsed: ");
    print_hex(t2 - t1);
    nv_print("\n");

    // Memory Test
    nv_print("Testing Malloc...\n");
    void* ptr = nv_malloc(1024);
    if (ptr) {
        nv_print("Allocated 1024 bytes at: ");
        print_hex((uint32_t)ptr);
        nv_print("\n");
        nv_free(ptr);
        nv_print("Memory freed.\n");
    } else {
        nv_print("Malloc failed!\n");
    }

    nv_print("\nPress any key to return to shell...");
    nv_getchar();
    nv_exit(0);
    return 0;
}
