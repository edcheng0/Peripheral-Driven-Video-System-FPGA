`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// top_camera_bars.v - top_camera_dvi with the camera's built-in color-bar
// test pattern switched on. Use this FIRST when testing the camera: if you
// see color bars on the monitor, the wiring, camera setup and the whole
// camera -> HDMI path work, independent of the lens or lighting.
// Same ports and same XDC files as top_camera_dvi.
// ----------------------------------------------------------------------
module top_camera_bars (
    input  wire       sysclk,
    input  wire [3:0] sw,
    output wire [3:0] led,
    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_p,
    output wire [2:0] hdmi_tx_n,
    input  wire [7:0] cam_d,
    input  wire       cam_pclk,
    input  wire       cam_vsync,
    input  wire       cam_href,
    output wire       cam_xclk,
    output wire       cam_reset_n,
    output wire       cam_pwdn,
    output wire       cam_sioc,
    inout  wire       cam_siod
);
    top_camera_dvi #(.TEST_BARS(1)) core (
        .sysclk(sysclk), .sw(sw), .led(led),
        .hdmi_tx_clk_p(hdmi_tx_clk_p), .hdmi_tx_clk_n(hdmi_tx_clk_n),
        .hdmi_tx_p(hdmi_tx_p), .hdmi_tx_n(hdmi_tx_n),
        .cam_d(cam_d), .cam_pclk(cam_pclk), .cam_vsync(cam_vsync), .cam_href(cam_href),
        .cam_xclk(cam_xclk), .cam_reset_n(cam_reset_n), .cam_pwdn(cam_pwdn),
        .cam_sioc(cam_sioc), .cam_siod(cam_siod)
    );
endmodule
