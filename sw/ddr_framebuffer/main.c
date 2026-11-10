/*
 * main.c - starts the video DMA (VDMA) so the camera picture goes through DDR3.
 *
 * What happens in hardware once this runs:
 *   - the VDMA's WRITE channel (S2MM) takes the camera's pixel stream and
 *     stores each 640x480 frame in one of 3 buffers in DDR3 (from FRAME_ADDR)
 *   - the VDMA READ channel (MM2S) follows the writer (genlock) and reads the newest complete frame,
 *     so the picture does not tear, and feeds it to the HDMI output
 * The ARM only sets the VDMA up; it never touches the pixels.
 *
 * Register offsets are from Xilinx's driver header xaxivdma_hw.h:
 *   read channel (MM2S):  CR 0x00  SR 0x04  VSIZE 0x50  HSIZE 0x54  STRIDE 0x58  ADDR0 0x5C
 *   write channel (S2MM): CR 0x30  SR 0x34  VSIZE 0xA0  HSIZE 0xA4  STRIDE 0xA8  ADDR0 0xAC
 */
#include <stdio.h>
#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h"
#include "sleep.h"
#include "xuartps_hw.h"

#if defined(XPAR_XAXIVDMA_0_BASEADDR)
#define VDMA_BASE XPAR_XAXIVDMA_0_BASEADDR
#elif defined(XPAR_AXI_VDMA_0_BASEADDR)
#define VDMA_BASE XPAR_AXI_VDMA_0_BASEADDR
#elif defined(XPAR_AXIVDMA_0_BASEADDR)
#define VDMA_BASE XPAR_AXIVDMA_0_BASEADDR
#else
#error "VDMA base address macro not found in xparameters.h"
#endif

#define GPIO_BASE_ADDR XPAR_XGPIO_0_BASEADDR   /* AXI GPIO: display filter mode */
#define STAT_BASE_ADDR XPAR_XGPIO_1_BASEADDR   /* AXI GPIO: camera/DMA counters (read only) */
#define FRAME_ADDR   0x08000000u   /* 128 MB into DDR3, well away from the program */
#define WIDTH        640
#define HEIGHT       480
#define BYTES_PER_PX 2             /* RGB565 */
#define LINE_BYTES   (WIDTH * BYTES_PER_PX)

/* per-channel register offsets */
#define MM2S_CR      0x00
#define MM2S_SR      0x04
#define MM2S_VSIZE   0x50
#define MM2S_HSIZE   0x54
#define MM2S_STRIDE  0x58
#define MM2S_ADDR0   0x5C

#define S2MM_CR      0x30
#define S2MM_SR      0x34
#define S2MM_VSIZE   0xA0
#define S2MM_HSIZE   0xA4
#define S2MM_STRIDE  0xA8
#define S2MM_ADDR0   0xAC

#define CR_RUN       0x1
#define CR_CIRCULAR  0x2   /* keep going frame after frame */
#define CR_GENLOCK   0x88  /* genlock enable (0x8) + internal genlock source (0x80): the reader follows the writer */
#define NUM_FRAMES   3
#define FRAME_STEP   0x00100000u   /* 1 MB between buffers (a frame is 600 KB) */
#define CR_RESET     0x4
#define SR_HALTED    0x1
#define SR_ERR_MASK  0x8FF0   /* error flags (bits 4-11 and 15) */
#define SR_IRQ_MASK  0x7000   /* interrupt flags, cleared too */

static void wr(unsigned off, unsigned v) { Xil_Out32(VDMA_BASE + off, v); }
static unsigned rd(unsigned off)         { return Xil_In32(VDMA_BASE + off); }

static void reset_channel(unsigned cr)
{
    wr(cr, CR_RESET);
    for (int i = 0; i < 1000 && (rd(cr) & CR_RESET); i++) usleep(10);
}

static void start_channel(unsigned cr, unsigned addr0, unsigned stride, unsigned hsize, unsigned vsize)
{
    wr(cr, CR_RUN | CR_CIRCULAR | CR_GENLOCK);
    for (int i = 0; i < NUM_FRAMES; i++) wr(addr0 + 4 * i, FRAME_ADDR + i * FRAME_STEP);
    wr(stride, LINE_BYTES);
    wr(hsize, LINE_BYTES);
    wr(vsize, HEIGHT);              /* writing VSIZE last starts the transfers */
}

/* ---- camera register access: the ARM wiggles the camera's SCCB (I2C-like) pins itself ----
 * GPIO output bits: [1:0] display mode, [2] camera re-init, [3] ARM owns the bus,
 *                   [4] pull SCL low, [5] pull SDA low.   GPIO input bit 9 = SDA level. */
static unsigned gpio_out = 0;
static void gpio_set(unsigned v) { gpio_out = v; Xil_Out32(GPIO_BASE_ADDR, v); }
static void scl(int high) { gpio_set(high ? (gpio_out & ~0x10u) : (gpio_out | 0x10u)); usleep(10); }
static void sda(int high) { gpio_set(high ? (gpio_out & ~0x20u) : (gpio_out | 0x20u)); usleep(10); }
static int  sda_read(void) { return (Xil_In32(GPIO_BASE_ADDR + 8) >> 9) & 1; }

static void sccb_recover(void)   /* free a slave that is holding SDA low: 9 clocks, then a stop */
{
    sda(1);
    for (int i = 0; i < 9; i++) { scl(0); scl(1); }
    sda(0); scl(1); sda(1);
}
static void sccb_start(void) { sda(1); scl(1); sda(0); scl(0); }
static void sccb_stop(void)  { sda(0); scl(1); sda(1); }
static void sccb_byte(unsigned b)
{
    for (int i = 7; i >= 0; i--) { sda((b >> i) & 1); scl(1); scl(0); }
    sda(1); scl(1); scl(0);                       /* 9th clock: ack ignored */
}
static unsigned sccb_rbyte(void)
{
    unsigned v = 0;
    sda(1);
    for (int i = 7; i >= 0; i--) { scl(1); v = (v << 1) | sda_read(); scl(0); }
    sda(1); scl(1); scl(0);                       /* 9th clock: no ack from master */
    return v;
}
static void cam_write(unsigned reg, unsigned val)
{
    sccb_start(); sccb_byte(0x42); sccb_byte(reg); sccb_byte(val); sccb_stop();
}
static unsigned cam_read(unsigned reg)
{
    sccb_start(); sccb_byte(0x42); sccb_byte(reg); sccb_stop();
    sccb_start(); sccb_byte(0x43); unsigned v = sccb_rbyte(); sccb_stop();
    return v;
}
static unsigned hex_digit(void)
{
    for (;;) {
        char c = inbyte();
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    }
}
static unsigned hex_byte(void) { unsigned h = hex_digit(); return (h << 4) | hex_digit(); }

static void cam_dump(void)
{
    static const unsigned regs[] = { 0x0A, 0x0B, 0x11, 0x12, 0x0C, 0x3E, 0x40, 0x3A, 0x3D,
                                     0x17, 0x18, 0x19, 0x1A, 0x32, 0x03, 0x70, 0x71, 0x72, 0x73, 0x15 };
    gpio_set(gpio_out | 8);                       /* take over the bus */
    sccb_recover();
    xil_printf("camera registers:");
    for (unsigned i = 0; i < sizeof(regs) / sizeof(regs[0]); i++)
        xil_printf(" %02x=%02x", regs[i], cam_read(regs[i]));
    xil_printf("\r\n");
    gpio_set(gpio_out & ~8u);                     /* hand the bus back */
}

int main(void)
{
    xil_printf("\r\nVDMA frame buffer setup\r\n");
    xil_printf("VDMA at 0x%08x, frame at 0x%08x, %dx%d RGB565\r\n",
               (unsigned)VDMA_BASE, FRAME_ADDR, WIDTH, HEIGHT);

    reset_channel(S2MM_CR);
    reset_channel(MM2S_CR);

    /* write side first so there is a frame to read */
    start_channel(S2MM_CR, S2MM_ADDR0, S2MM_STRIDE, S2MM_HSIZE, S2MM_VSIZE);
    start_channel(MM2S_CR, MM2S_ADDR0, MM2S_STRIDE, MM2S_HSIZE, MM2S_VSIZE);

    gpio_set(0);
    xil_printf("Keys: 0-3 filter | r re-send camera settings | d dump camera registers | gHH read reg | wHHVV write reg\r\n");

    int ticks = 0;
    unsigned w_errs = 0, r_errs = 0, w_restarts = 0, r_restarts = 0, w_last = 0, r_last = 0;
    while (1) {
        if (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
            char c = inbyte();
            if (c >= '0' && c <= '3') { gpio_set((gpio_out & ~3u) | (unsigned)(c - '0')); xil_printf("mode = %d\r\n", c - '0'); }
            if (c == 'r') {
                gpio_set(gpio_out | 4);       /* camera held in reset */
                usleep(50000);
                gpio_set(gpio_out & ~4u);     /* released: settings are sent again */
                xil_printf("camera re-init requested\r\n");
            }
            if (c == 'd') cam_dump();
            if (c == 'p') {
                gpio_set(gpio_out | 8);
                unsigned before = Xil_In32(GPIO_BASE_ADDR + 8);
                sccb_recover();
                sda(1); scl(1);
                xil_printf("SDA before recovery: %u\r\n", (before >> 9) & 1);
                unsigned hi = Xil_In32(GPIO_BASE_ADDR + 8);
                sda(0);
                unsigned lo = Xil_In32(GPIO_BASE_ADDR + 8);
                sda(1);
                gpio_set(gpio_out & ~8u);
                xil_printf("SDA released: gpio_in=%03x (bit9=%u), SDA pulled low: gpio_in=%03x (bit9=%u)\r\n",
                           hi, (hi >> 9) & 1, lo, (lo >> 9) & 1);
            }
            if (c == 'g') {
                unsigned reg = hex_byte();
                gpio_set(gpio_out | 8);
                unsigned v = cam_read(reg);
                gpio_set(gpio_out & ~8u);
                xil_printf("reg %02x = %02x\r\n", reg, v);
            }
            if (c == 'w') {
                unsigned reg = hex_byte(), val = hex_byte();
                gpio_set(gpio_out | 8);
                cam_write(reg, val);
                gpio_set(gpio_out & ~8u);
                xil_printf("reg %02x <- %02x\r\n", reg, val);
            }
        }
        usleep(1000);

        /* every millisecond: log and clear errors; restart a channel that has stopped */
        unsigned ws = rd(S2MM_SR), rs = rd(MM2S_SR);
        if (ws & SR_ERR_MASK) { w_errs++; w_last = ws; }
        if (rs & SR_ERR_MASK) { r_errs++; r_last = rs; }
        if (ws & (SR_ERR_MASK | SR_IRQ_MASK)) wr(S2MM_SR, ws & (SR_ERR_MASK | SR_IRQ_MASK));
        if (rs & (SR_ERR_MASK | SR_IRQ_MASK)) wr(MM2S_SR, rs & (SR_ERR_MASK | SR_IRQ_MASK));
        if (ws & SR_HALTED) { w_restarts++; reset_channel(S2MM_CR); start_channel(S2MM_CR, S2MM_ADDR0, S2MM_STRIDE, S2MM_HSIZE, S2MM_VSIZE); }
        if (rs & SR_HALTED) { r_restarts++; reset_channel(MM2S_CR); start_channel(MM2S_CR, MM2S_ADDR0, MM2S_STRIDE, MM2S_HSIZE, MM2S_VSIZE); }

        if (++ticks < 2000) continue;
        ticks = 0;
        unsigned sa = Xil_In32(STAT_BASE_ADDR), sb = Xil_In32(STAT_BASE_ADDR + 8);
        xil_printf("cam: href clocks/line %u, lines/frame %u, frames %u, refused beats %u\r\n",
                   sa & 0xFFFF, sa >> 16, sb & 0xFFFF, sb >> 16);
        unsigned cs = Xil_In32(GPIO_BASE_ADDR + 8);
        xil_printf("camera: init_done %u, unacknowledged writes %u | ", (cs >> 8) & 1, cs & 0xFF);
        xil_printf("write: errors %u last SR %08x restarts %u | read: errors %u last SR %08x restarts %u\r\n",
                   w_errs, w_last, w_restarts, r_errs, r_last, r_restarts);
    }
    return 0;
}
