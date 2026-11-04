`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tmds_serializer.v - sends one 10-bit TMDS word per pixel clock out of
// ONE differential pin pair, least-significant bit first.
//
// What is an OSERDESE2? It is a "serializer" block that sits right next
// to an output pin. You hand it several bits in parallel on a slow clock
// (CLKDIV = our pixel clock) and it shifts them out one after another on
// a fast clock (CLK = our serial clock). In DDR mode it sends one bit on
// each rising AND falling edge of CLK, so 5 CLK cycles = 10 bits.
//
// One OSERDESE2 can only take up to 8 bits in DDR mode. To reach 10 bits
// we use two of them chained: a "master" that drives the pin and a
// "slave" that supplies the extra bits (bits 8 and 9) through the
// SHIFTIN/SHIFTOUT wires between them.
//
// OBUFDS is the output buffer that drives the two pins of a pair with
// opposite polarity (TMDS_33 = the DVI/HDMI signal level; set in the XDC).
//
// clk_serial MUST be exactly 5x clk_pixel and from the same MMCM (see
// video_clocks.v). Keep rst high until the MMCM is locked.
// ----------------------------------------------------------------------
module tmds_serializer (
    input  wire       clk_pixel,   // slow clock: one 10-bit word per tick
    input  wire       clk_serial,  // fast clock: 5x clk_pixel
    input  wire       rst,         // active-high, hold until MMCM locked
    input  wire [9:0] data,        // TMDS word; bit 0 is sent first
    output wire       out_p,
    output wire       out_n
);

    wire serial_bit;
    wire shift1, shift2;   // slave -> master shift wires

    OSERDESE2 #(
        .DATA_RATE_OQ ("DDR"),
        .DATA_RATE_TQ ("SDR"),
        .DATA_WIDTH   (10),
        .SERDES_MODE  ("MASTER"),
        .TRISTATE_WIDTH(1)
    ) oserdes_master (
        .OQ        (serial_bit),
        .OFB       (),
        .TQ        (),
        .TFB       (),
        .SHIFTOUT1 (),
        .SHIFTOUT2 (),
        .CLK       (clk_serial),
        .CLKDIV    (clk_pixel),
        .D1        (data[0]),
        .D2        (data[1]),
        .D3        (data[2]),
        .D4        (data[3]),
        .D5        (data[4]),
        .D6        (data[5]),
        .D7        (data[6]),
        .D8        (data[7]),
        .OCE       (1'b1),
        .RST       (rst),
        .SHIFTIN1  (shift1),
        .SHIFTIN2  (shift2),
        .T1        (1'b0),
        .T2        (1'b0),
        .T3        (1'b0),
        .T4        (1'b0),
        .TBYTEIN   (1'b0),
        .TBYTEOUT  (),
        .TCE       (1'b0)
    );

    OSERDESE2 #(
        .DATA_RATE_OQ ("DDR"),
        .DATA_RATE_TQ ("SDR"),
        .DATA_WIDTH   (10),
        .SERDES_MODE  ("SLAVE"),
        .TRISTATE_WIDTH(1)
    ) oserdes_slave (
        .OQ        (),
        .OFB       (),
        .TQ        (),
        .TFB       (),
        .SHIFTOUT1 (shift1),
        .SHIFTOUT2 (shift2),
        .CLK       (clk_serial),
        .CLKDIV    (clk_pixel),
        .D1        (1'b0),
        .D2        (1'b0),
        .D3        (data[8]),
        .D4        (data[9]),
        .D5        (1'b0),
        .D6        (1'b0),
        .D7        (1'b0),
        .D8        (1'b0),
        .OCE       (1'b1),
        .RST       (rst),
        .SHIFTIN1  (1'b0),
        .SHIFTIN2  (1'b0),
        .T1        (1'b0),
        .T2        (1'b0),
        .T3        (1'b0),
        .T4        (1'b0),
        .TBYTEIN   (1'b0),
        .TBYTEOUT  (),
        .TCE       (1'b0)
    );

    OBUFDS #(.IOSTANDARD("TMDS_33")) obuf (
        .I  (serial_bit),
        .O  (out_p),
        .OB (out_n)
    );

endmodule
