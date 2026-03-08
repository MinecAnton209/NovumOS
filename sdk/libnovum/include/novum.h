#ifndef NOVUM_H
#define NOVUM_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

// --- System Types ---
typedef uint32_t nv_size_t;
typedef int32_t  nv_status_t;

typedef struct {
    uint16_t year;
    uint8_t month;
    uint8_t day;
    uint8_t hour;
    uint8_t minute;
    uint8_t second;
} nv_datetime_t;

// --- Syscall Constants ---
#define SYS_EXIT           0
#define SYS_PRINT          1
#define SYS_GETCHAR        2
#define SYS_SET_CURSOR     3
#define SYS_GET_CURSOR     4
#define SYS_CLEAR_SCREEN   5
#define SYS_INB            6
#define SYS_OUTB           7
#define SYS_INW            8
#define SYS_OUTW           9
#define SYS_SLEEP          10
#define SYS_GET_TICKS      11
#define SYS_SHUTDOWN       13
#define SYS_REBOOT         14
#define SYS_MMAP_RANGE     15
#define SYS_INL            16
#define SYS_OUTL           17
#define SYS_DRAW_CHAR_AT   18
#define SYS_GET_DATETIME   19
#define SYS_ATA_IDENTIFY   20
#define SYS_ATA_READ       21
#define SYS_ATA_WRITE      22
#define SYS_MALLOC         30
#define SYS_FREE           31
#define SYS_CHECK_CTRL_C   32

// --- Core API ---

/**
 * Exit the current process.
 */
void nv_exit(int code);

/**
 * Print a null-terminated string to the console.
 */
void nv_print(const char* str);

/**
 * Wait for a keyboard character and return it.
 */
uint8_t nv_getchar(void);

/**
 * Clear the VGA screen.
 */
void nv_clear_screen(void);

/**
 * Set the hardware cursor position.
 */
void nv_set_cursor(uint8_t row, uint8_t col);

/**
 * Get current hardware cursor position.
 */
void nv_get_cursor(uint8_t* row, uint8_t* col);

/**
 * Sleep for a specified number of milliseconds.
 */
void nv_sleep(uint32_t ms);

/**
 * Get current system timer ticks.
 */
uint32_t nv_get_ticks(void);

/**
 * Shutdown the system.
 */
void nv_shutdown(void);

/**
 * Reboot the system.
 */
void nv_reboot(void);

/**
 * Map a virtual memory range.
 */
void nv_mmap_range(uint32_t vaddr, uint32_t size);

/**
 * Draw a character at a specific location with an attribute.
 */
void nv_draw_char_at(uint8_t row, uint8_t col, uint8_t c, uint16_t attr);

/**
 * Get current system date and time.
 */
void nv_get_datetime(nv_datetime_t* dt);

/**
 * I/O Port operations.
 */
uint8_t  nv_inb(uint16_t port);
void     nv_outb(uint16_t port, uint8_t val);
uint16_t nv_inw(uint16_t port);
void     nv_outw(uint16_t port, uint16_t val);
uint32_t nv_inl(uint16_t port);
void     nv_outl(uint16_t port, uint32_t val);

/**
 * Memory Management.
 */
void* nv_malloc(uint32_t size);
void  nv_free(void* ptr);

/**
 * Check if Ctrl+C was pressed.
 */
int nv_check_ctrl_c(void);

#ifdef __cplusplus
}
#endif

#endif // NOVUM_H
