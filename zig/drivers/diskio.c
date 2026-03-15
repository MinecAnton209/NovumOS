// Custom diskio.c for NovumOS - implements FatFS low-level disk I/O
#include <stdint.h>
#include "novum_libc.h"

// Define FatFS types before including headers
typedef uint8_t BYTE;
typedef uint16_t WORD;
typedef uint32_t DWORD;
typedef uint32_t LBA_t;
typedef uint32_t UINT;

// Disable string.h include in FatFS
#define _STRING_H

// Include FatFS headers
#include "ff.h"
#include "diskio.h"

// External ATA driver functions from Zig
extern void ata_read_sector(uint8_t drive, uint32_t lba, uint8_t* buffer);
extern void ata_write_sector(uint8_t drive, uint32_t lba, const uint8_t* buffer);

// Disk status
static DSTATUS Stat = STA_NOINIT;

// Initialize disk
DSTATUS disk_initialize(BYTE pdrv) {
    (void)pdrv;
    Stat = 0;  // Assume OK
    return Stat;
}

// Get disk status
DSTATUS disk_status(BYTE pdrv) {
    (void)pdrv;
    return Stat;
}

// Read sectors
DRESULT disk_read(BYTE pdrv, BYTE* buff, LBA_t sector, UINT count) {
    (void)pdrv;
    
    for (UINT i = 0; i < count; i++) {
        ata_read_sector(0, sector + i, buff + (i * 512));
    }
    return RES_OK;
}

// Write sectors
DRESULT disk_write(BYTE pdrv, const BYTE* buff, LBA_t sector, UINT count) {
    (void)pdrv;
    
    for (UINT i = 0; i < count; i++) {
        ata_write_sector(0, sector + i, buff + (i * 512));
    }
    return RES_OK;
}

// Disk I/O control
DRESULT disk_ioctl(BYTE pdrv, BYTE cmd, void* buff) {
    (void)pdrv;
    (void)buff;
    
    switch (cmd) {
        case CTRL_SYNC:
            return RES_OK;
        case GET_SECTOR_COUNT:
            return RES_PARERR;
        case GET_SECTOR_SIZE:
            return RES_PARERR;
        case GET_BLOCK_SIZE:
            return RES_PARERR;
        default:
            return RES_PARERR;
    }
}
