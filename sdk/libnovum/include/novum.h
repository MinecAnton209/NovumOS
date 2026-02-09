#ifndef NOVUM_H
#define NOVUM_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

// --- System Types ---
typedef uint32_t nv_size_t;
typedef int32_t  nv_status_t;

// --- Syscall Constants ---
#define SYS_EXIT         0
#define SYS_PRINT        1
#define SYS_GETCHAR      2
#define SYS_SET_CURSOR   3
#define SYS_GET_CURSOR   4
#define SYS_CLEAR_SCREEN 5

// --- Core API ---

/**
 * Exit the current process.
 * @param code Exit status code.
 */
void nv_exit(int code);

/**
 * Print a null-terminated string to the console.
 * @param str The string to print.
 */
void nv_print(const char* str);

/**
 * Wait for a keyboard character and return it.
 * @return ASCII character code.
 */
uint8_t nv_getchar(void);

/**
 * Clear the VGA screen.
 */
void nv_clear_screen(void);

/**
 * Set the hardware cursor position.
 * @param row Row (0-24)
 * @param col Column (0-79)
 */
void nv_set_cursor(uint8_t row, uint8_t col);

/**
 * Get current hardware cursor position.
 * @param row Pointer to store row.
 * @param col Pointer to store column.
 */
void nv_get_cursor(uint8_t* row, uint8_t* col);

#ifdef __cplusplus
}
#endif

#endif // NOVUM_H
