`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tmds_tx_lanes.v - everything between "RGB pixel + sync" and the HDMI pins.
//
// 3 TMDS encoders (blue's also carries hsync/vsync) + 4 serializers (the
// 4th sends the clock lane). Shared by the color-bar tops and the camera
// top so the HDMI output logic exists in exactly one place.
//
// Inputs hsync/vsync are ACTIVE-HIGH pulses (as video_timing_gen makes
// them). SYNC_ACTIVE_LOW=1 inverts them for 640x480.
// All inputs must be in the clk_pixel domain and aligned with each other.
// ----------------------------------------------------------------------
module tmds_tx_lanes #(
    parameter SYNC_ACTIVE_LOW = 1
) (
    input  wire       clk_pixel,
    input  wire       clk_serial,   // exactly 5x clk_pixel, edge-aligned
    input  wire       rst,          // pixel-domain reset (held until MMCM locked)
    input  wire [7:0] red,
    input  wire [7:0] green,
    input  wire [7:0] blue,
    input  wire       hsync,
    input  wire       vsync,
    input  wire       de,

    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,     // [0]=blue [1]=green [2]=red
    output wire [2:0] tmds_d_n
);

    wire hsync_out = SYNC_ACTIVE_LOW ? ~hsync : hsync;
    wire vsync_out = SYNC_ACTIVE_LOW ? ~vsync : vsync;

    wire [9:0] word_b, word_g, word_r;
    tmds_encoder u_enc_b (.clk(clk_pixel), .rst(rst), .data_in(blue),
                          .control_in({vsync_out, hsync_out}), .data_enable(de),
                          .tmds_out(word_b));
    tmds_encoder u_enc_g (.clk(clk_pixel), .rst(rst), .data_in(green),
                          .control_in(2'b00), .data_enable(de),
                          .tmds_out(word_g));
    tmds_encoder u_enc_r (.clk(clk_pixel), .rst(rst), .data_in(red),
                          .control_in(2'b00), .data_enable(de),
                          .tmds_out(word_r));

    tmds_serializer u_ser_b (.clk_pixel(clk_pixel), .clk_serial(clk_serial),
                             .rst(rst), .data(word_b),
                             .out_p(tmds_d_p[0]), .out_n(tmds_d_n[0]));
    tmds_serializer u_ser_g (.clk_pixel(clk_pixel), .clk_serial(clk_serial),
                             .rst(rst), .data(word_g),
                             .out_p(tmds_d_p[1]), .out_n(tmds_d_n[1]));
    tmds_serializer u_ser_r (.clk_pixel(clk_pixel), .clk_serial(clk_serial),
                             .rst(rst), .data(word_r),
                             .out_p(tmds_d_p[2]), .out_n(tmds_d_n[2]));
    tmds_serializer u_ser_c (.clk_pixel(clk_pixel), .clk_serial(clk_serial),
                             .rst(rst), .data(10'b0000011111),
                             .out_p(tmds_clk_p), .out_n(tmds_clk_n));

endmodule
