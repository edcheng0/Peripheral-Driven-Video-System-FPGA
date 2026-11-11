/*
 * net_stream.c - sends the camera video over Ethernet (UDP) using the lwIP network stack.
 *
 *   Board: 192.168.1.10, UDP port 5000.  PC: 192.168.1.1 (set a fixed IP on the PC's Ethernet adapter).
 *   The PC viewer (pc/stream_viewer.cs) sends a small "hello" packet to the board; the board then
 *   streams the newest complete camera frame back to the sender, one UDP packet per image line:
 *       u32 frame number | u16 line | u16 payload bytes (1280) | 640 pixels RGB565 (little endian)
 *   The stream stops a few seconds after the hellos stop.  lwIP also answers ping (ICMP) by itself.
 *
 * lwIP runs in "raw" mode here: no operating system, the main loop calls net_poll() all the time.
 * The Ethernet link (PHY) is only started once a cable with a live partner is detected, because
 * the PHY set-up code waits forever for the link, which would freeze the whole program (video
 * and servo included) when nothing is plugged in.
 */
#include <string.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xiltimer.h"
#include "xtimer_config.h"
#include "xscugic.h"
#include "xemacps.h"
#include "netif/xadapter.h"
#include "lwip/init.h"
#include "lwip/udp.h"
#include "lwip/pbuf.h"
#include "net_stream.h"

#define VDMA_PARK_PTR   0x28            /* read: bits 20:16 = frame store the reader is showing now */
#define FRAME_ADDR      0x08000000u
#define FRAME_STEP      0x00100000u
#define NUM_FRAMES      3
#define WIDTH           640
#define HEIGHT          480
#define LINE_BYTES      (WIDTH * 2)
#define FRAME_BYTES     (LINE_BYTES * HEIGHT)
#define HDR_BYTES       8
#define UDP_PORT        5000
#define FRAME_PERIOD_MS 100             /* 10 frames per second */
#define LINES_PER_POLL  16
#define HELLO_TIMEOUT_MS 3000

extern unsigned vdma_base(void);        /* provided by main.c */

static struct netif the_netif;
static struct udp_pcb *pcb;
static int net_up = 0;

static ip_addr_t peer_ip;
static u16_t peer_port;
static int have_peer = 0;
static unsigned long long last_hello;

static unsigned char snap[FRAME_BYTES] __attribute__((aligned(64)));   /* copy of one frame */
static unsigned frame_id = 0, cur_line = HEIGHT;                        /* HEIGHT = idle */
static unsigned long long next_frame, next_link_check;
static unsigned frames_sent = 0, send_fails = 0;

static unsigned long long ms_now(void)
{
    XTime t; XTime_GetTime(&t);
    return t / (COUNTS_PER_SECOND / 1000);
}

/* Is there a live link partner?  Reads the PHY status over MDIO without starting autonegotiation. */
static int link_is_up(void)
{
    static XEmacPs mac;
    static int inited = 0;
    if (!inited) {
        XEmacPs_Config cfg;
        memset(&cfg, 0, sizeof(cfg));
        cfg.BaseAddress = XPAR_XEMACPS_0_BASEADDR;
        if (XEmacPs_CfgInitialize(&mac, &cfg, cfg.BaseAddress) != XST_SUCCESS) return 0;
        XEmacPs_SetMdioDivisor(&mac, MDC_DIV_224);
        inited = 1;
    }
    for (u32 addr = 0; addr < 32; addr++) {
        u16 id = 0, st = 0;
        if (XEmacPs_PhyRead(&mac, addr, 2, &id) != XST_SUCCESS) continue;
        if (id == 0xFFFF || id == 0) continue;               /* nobody at this address */
        XEmacPs_PhyRead(&mac, addr, 1, &st);                 /* link bit is latched low: read twice */
        XEmacPs_PhyRead(&mac, addr, 1, &st);
        return (st & 0x4) != 0;                              /* bit 2 = link up */
    }
    return 0;
}

static void on_receive(void *arg, struct udp_pcb *p, struct pbuf *pb, const ip_addr_t *addr, u16_t port)
{
    (void)arg; (void)p;
    ip_addr_copy(peer_ip, *addr);
    peer_port = port;
    if (!have_peer) xil_printf("net: viewer connected from %d.%d.%d.%d:%d\r\n",
                               ip4_addr1(addr), ip4_addr2(addr), ip4_addr3(addr), ip4_addr4(addr), port);
    have_peer = 1;
    last_hello = ms_now();
    pbuf_free(pb);
}

static void net_start(void)
{
    static const unsigned char mac_addr[6] = { 0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };
    ip_addr_t ip, mask, gw;

    /* interrupt controller + exceptions: the Ethernet driver needs them for receive/transmit events */
    Xil_ExceptionInit();
    XScuGic_DeviceInitialize(XPAR_SCUGIC_SINGLE_DEVICE_ID);
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_IRQ_INT,
                                 (Xil_ExceptionHandler)XScuGic_DeviceInterruptHandler,
                                 (void *)XPAR_SCUGIC_SINGLE_DEVICE_ID);
    Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);

    IP4_ADDR(&ip,   192, 168, 1, 10);
    IP4_ADDR(&mask, 255, 255, 255, 0);
    IP4_ADDR(&gw,   192, 168, 1, 1);

    lwip_init();
    if (!xemac_add(&the_netif, &ip, &mask, &gw, (unsigned char *)mac_addr, XPAR_XEMACPS_0_BASEADDR)) {
        xil_printf("net: could not add the network interface\r\n");
        return;
    }
    netif_set_default(&the_netif);
    netif_set_up(&the_netif);

    pcb = udp_new();
    if (!pcb || udp_bind(pcb, IP_ADDR_ANY, UDP_PORT) != ERR_OK) {
        xil_printf("net: could not open UDP port %d\r\n", UDP_PORT);
        return;
    }
    udp_recv(pcb, on_receive, NULL);
    net_up = 1;
    xil_printf("net: up, board IP 192.168.1.10, UDP port %d (answers ping, streams to a viewer)\r\n", UDP_PORT);
}

/* copy the frame the display is showing right now (that buffer is not being written) */
static void snapshot_frame(void)
{
    unsigned idx = (Xil_In32(vdma_base() + VDMA_PARK_PTR) >> 16) & 0x1F;
    if (idx >= NUM_FRAMES) idx = 0;
    unsigned src = FRAME_ADDR + idx * FRAME_STEP;
    Xil_DCacheInvalidateRange(src, FRAME_BYTES);
    memcpy(snap, (const void *)src, FRAME_BYTES);
}

static void stream_lines(void)
{
    for (int n = 0; n < LINES_PER_POLL && cur_line < HEIGHT; n++) {
        struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, HDR_BYTES + LINE_BYTES, PBUF_RAM);
        if (!p) { send_fails++; return; }
        unsigned char *d = (unsigned char *)p->payload;
        memcpy(d + 0, &frame_id, 4);
        u16_t line = (u16_t)cur_line, len = LINE_BYTES;
        memcpy(d + 4, &line, 2);
        memcpy(d + 6, &len, 2);
        memcpy(d + HDR_BYTES, snap + cur_line * LINE_BYTES, LINE_BYTES);
        err_t e = udp_sendto(pcb, p, &peer_ip, peer_port);
        pbuf_free(p);
        if (e != ERR_OK) { send_fails++; return; }       /* transmit queue full: retry this line next time */
        cur_line++;
    }
    if (cur_line >= HEIGHT) frames_sent++;
}

void net_poll(void)
{
    unsigned long long now = ms_now();

    if (!net_up) {
        if (now < next_link_check) return;
        next_link_check = now + 1000;
        if (link_is_up()) net_start();
        return;
    }

    xemacif_input(&the_netif);

    if (have_peer && now - last_hello > HELLO_TIMEOUT_MS) {
        have_peer = 0;
        cur_line = HEIGHT;
        xil_printf("net: viewer stopped\r\n");
    }
    if (!have_peer) return;

    if (cur_line >= HEIGHT && now >= next_frame) {
        next_frame = now + FRAME_PERIOD_MS;
        snapshot_frame();
        frame_id++;
        cur_line = 0;
    }
    if (cur_line < HEIGHT) stream_lines();
}

void net_status(void)
{
    xil_printf("net: %s, streaming %s, frames sent %u, send failures %u\r\n",
               net_up ? "up" : "no link", have_peer ? "yes" : "no", frames_sent, send_fails);
}
