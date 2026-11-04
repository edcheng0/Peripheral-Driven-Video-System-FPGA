`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// top_dvi_720p.v - same color-bar design as top_phase1_dvi, but 1280x720@60
// (CEA 720p): ~74.22 MHz pixel clock (standard is 74.25, -0.04%), ~742 Mb/s
// per TMDS lane, positive sync.
//   total 1650 x 750 ; h: 1280+110+40+220 ; v: 720+5+5+20
//   MMCM: 125/8 = 15.625 MHz x 47.5 = 742.1875 MHz VCO
//         -> /2 = 371.09 MHz serial, /10 = 74.22 MHz pixel
// This is a much faster signal than the other modes; check the -1 speed
// grade timing report (WNS) before trusting it on hardware.
// Same ports and same XDC files as top_phase1_dvi (Zybo Z7-20).
// ----------------------------------------------------------------------
module top_dvi_720p (
    input  wire       sysclk,
    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_p,
    output wire [2:0] hdmi_tx_n
);
    top_phase1_dvi #(
        .CNT_W(11),
        .H_VISIBLE(1280), .H_FRONT_PORCH(110), .H_SYNC_PULSE(40), .H_BACK_PORCH(220),
        .V_VISIBLE(720),  .V_FRONT_PORCH(5),   .V_SYNC_PULSE(5),  .V_BACK_PORCH(20),
        .SYNC_ACTIVE_LOW(0),
        .DIVCLK_DIVIDE(8), .CLKFBOUT_MULT_F(47.5),
        .SERIAL_DIVIDE_F(2.0), .PIXEL_DIVIDE(10)
    ) core (
        .sysclk(sysclk),
        .hdmi_tx_clk_p(hdmi_tx_clk_p), .hdmi_tx_clk_n(hdmi_tx_clk_n),
        .hdmi_tx_p(hdmi_tx_p), .hdmi_tx_n(hdmi_tx_n)
    );
endmodule
