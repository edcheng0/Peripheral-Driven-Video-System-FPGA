/*
 * main.c - ARM program that picks the video filter.
 *
 * Open a serial terminal on the Zybo's UART (115200 baud, 8N1) and type:
 *   0 = raw color    1 = grayscale    2 = edge detect (Sobel)    3 = invert
 * The ARM writes the number to an AXI GPIO block; the FPGA video pipeline
 * reads it as its filter mode, and the program prints which mode was chosen.
 */
#include <stdio.h>
#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h"

/* AXI GPIO: channel 1 data register is at offset 0x0 */
#define GPIO_BASE  XPAR_XGPIO_0_BASEADDR
#define GPIO_DATA  (GPIO_BASE + 0x0)

static const char *mode_name(int m)
{
    switch (m) {
    case 0:  return "raw color";
    case 1:  return "grayscale";
    case 2:  return "edge detect";
    default: return "invert";
    }
}

int main(void)
{
    xil_printf("\r\nVideo filter control\r\n");
    xil_printf("Type 0 (raw), 1 (gray), 2 (edges), 3 (invert)\r\n");

    Xil_Out32(GPIO_DATA, 0);

    while (1) {
        char c = inbyte();              /* wait for a key */
        if (c >= '0' && c <= '3') {
            int m = c - '0';
            Xil_Out32(GPIO_DATA, m);
            xil_printf("mode = %d (%s)\r\n", m, mode_name(m));
        }
    }
    return 0;
}
