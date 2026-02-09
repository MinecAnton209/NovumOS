#include <novum.h>

// Simple calculator demo for NovumOS
// Demonstrates basic I/O and user interaction

int main() {
    nv_clear_screen();
    nv_set_cursor(2, 10);
    nv_print("=== NovumOS Calculator ===");
    
    nv_set_cursor(4, 10);
    nv_print("This is a demo application");
    
    nv_set_cursor(5, 10);
    nv_print("showing SDK capabilities.");
    
    nv_set_cursor(7, 10);
    nv_print("Press any key to exit...");
    
    nv_getchar();
    nv_exit(0);
    return 0;
}
