#include <stdint.h>
#include <string.h>
#include <time.h>

#include "doomgeneric.h"

static uint32_t fb_vaddr = 0;
static int fb_width = 0, fb_height = 0, fb_pitch = 0, fb_bpp = 0;

struct video_mode { uint32_t w, h, bpp, pitch; };

static void get_video_mode(struct video_mode *m) {
    asm volatile("int $0x80" : "=a"(m->w) : "a"(60), "b"((uint32_t)(uintptr_t)m) : "memory");
}

static uint32_t request_fb(void) {
    uint32_t r;
    asm volatile("int $0x80" : "=a"(r) : "a"(61) : "memory");
    return r;
}

struct input_ev { uint32_t type, code; int32_t v1, v2, v3; };

static int poll_ev(struct input_ev *e) {
    int r;
    asm volatile("int $0x80" : "=a"(r) : "a"(63), "b"((uint32_t)(uintptr_t)e) : "memory");
    return r;
}

#define KQ 64
static int kq_p[KQ];
static unsigned char kq_k[KQ];
static int kq_h, kq_t;

static const unsigned char s2d[] = {
    0,27,'1','2','3','4','5','6','7','8',
    '9','0','-','=',127,9,
    'q','w','e','r','t','y','u','i','o','p',
    '[',']',13,0,'a','s',
    'd','f','g','h','j','k','l',';','\'','`',
    0,'\\','z','x','c','v',
    'b','n','m',',','.','/',0,'*',0,' ',
};

static const unsigned char e2d[] = {
    0x47,0x85,0x48,0xad,0x49,0x8a,0x4b,0xac,
    0x4d,0xae,0x4f,0x86,0x50,0xaf,0x51,0x8b,
    0x52,0x84,0x53,0x87,
};

static unsigned char map_key(unsigned char sc) {
    unsigned char k;
    if (sc & 0x80) {
        sc &= 0x7f;
        for (int i = 0; i < (int)sizeof(e2d); i += 2)
            if (e2d[i] == sc) return e2d[i+1];
        return 0;
    }
    if (sc >= sizeof(s2d)) return 0;
    k = s2d[sc];
    if (k == 0) {
        if (sc==0x36) k=0xb6; else if (sc==0x38) k=0xb8;
        else if (sc==0x1d) k=0x9d; else if (sc>=0x3b && sc<=0x44) k=0xbb+(sc-0x3b);
        else if (sc==0x57) k=0xd7; else if (sc==0x58) k=0xd8;
    }
    return k;
}

void DG_Init(void) {
    struct video_mode vm;
    get_video_mode(&vm);
    fb_width = vm.w; fb_height = vm.h; fb_bpp = vm.bpp; fb_pitch = vm.pitch;
    fb_vaddr = request_fb();
}

void DG_DrawFrame(void) {
    uint32_t *fb = (uint32_t *)fb_vaddr;
    pixel_t *src = DG_ScreenBuffer;
    int w = DOOMGENERIC_RESX, h = DOOMGENERIC_RESY;
    if (fb_width == w && fb_height == h && fb_pitch == w*4) {
        memcpy(fb, src, w*h*4);
    } else {
        int sw = w < fb_width ? w : fb_width;
        int sh = h < fb_height ? h : fb_height;
        for (int y = 0; y < sh; y++)
            memcpy((uint8_t*)fb + y*fb_pitch, (uint8_t*)src + y*w*4, sw*4);
    }
}

void DG_SleepMs(uint32_t ms) {
    struct timespec ts = { ms/1000, (ms%1000)*1000000L };
    nanosleep(&ts, NULL);
}

static uint32_t base_ms = 0;

uint32_t DG_GetTicksMs(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint32_t now = ts.tv_sec*1000 + ts.tv_nsec/1000000;
    if (!base_ms) base_ms = now;
    return now - base_ms;
}

int DG_GetKey(int *pressed, unsigned char *dk) {
    if (kq_h != kq_t) {
        *pressed = kq_p[kq_t]; *dk = kq_k[kq_t];
        kq_t = (kq_t+1)%KQ;
        return 1;
    }
    struct input_ev ev;
    while (poll_ev(&ev)) {
        if (ev.type == 1 || ev.type == 2) {
            unsigned char k = map_key((unsigned char)ev.code);
            if (k) {
                int n = (kq_h+1)%KQ;
                if (n != kq_t) { kq_p[kq_h]=(ev.type==1); kq_k[kq_h]=k; kq_h=n; }
            }
        }
    }
    if (kq_h != kq_t) {
        *pressed = kq_p[kq_t]; *dk = kq_k[kq_t];
        kq_t = (kq_t+1)%KQ;
        return 1;
    }
    return 0;
}

void DG_SetWindowTitle(const char *t) { (void)t; }

int main(int argc, char **argv) {
    doomgeneric_Create(argc, argv);
    for (;;) doomgeneric_Tick();
}
