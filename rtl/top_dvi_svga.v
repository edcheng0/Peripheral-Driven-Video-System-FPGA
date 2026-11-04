`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// top_dvi_svga.v - same color-bar design as top_phase1_dvi, but 800x600@60
// (VESA SVGA): 40 MHz pixel clock, 400 Mb/s per TMDS lane, positive sync.
//   total 1056 x 628 ; h: 800+40+128+88 ; v: 600+1+4+23
//   MMCM: 125 MHz / 5 x 32 = 800 MHz VCO -> /4 = 200 MHz serial, /20 = 40 MHz pixel
// Same ports and same XDC files as top_phase1_dvi (Zybo Z7-20).
// ----------------------------------------------------------------------
module top_dvi_svga (
    input  wire       sysclk,
    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_p,
    output wire [2:0] hdmi_tx_n
);
    top_phase1_dvi #(
        .CNT_W(11),
        .H_VISIBLE(800), .H_FRONT_PORCH(40), .H_SYNC_PULSE(128), .H_BACK_PORCH(88),
        .V_VISIBLE(600), .V_FRONT_PORCH(1),  .V_SYNC_PULSE(4),   .V_BACK_PORCH(23),
        .SYNC_ACTIVE_LOW(0),
        .DIVCLK_DIVIDE(5), .CLKFBOUT_MULT_F(32.0),
        .SERIAL_DIVIDE_F(4.0), .PIXEL_DIVIDE(20)
    ) core (
        .sysclk(sysclk),
        .hdmi_tx_clk_p(hdmi_tx_clk_p), .hdmi_tx_clk_n(hdmi_tx_clk_n),
        .hdmi_tx_p(hdmi_tx_p), .hdmi_tx_n(hdmi_tx_n)
    );
endmodule
