#include <novum.h>

int main() {
    nv_clear_screen();
    nv_set_cursor(10, 30);
    nv_print("Hello from ELF User Mode!");
    nv_set_cursor(12, 30);
    nv_print("Press any key to exit...");
    
    nv_getchar();
    
    nv_exit(0);
    return 0; // Unreachable
}
