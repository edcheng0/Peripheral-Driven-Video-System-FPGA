`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// video_sink.v - AXI4-Stream video in, HDMI pins out (640x480@60).
//   video_timing_gen  : when is each pixel wanted?
//   axis_video_out    : lines the DMA's pixel stream up with that timing
//   tmds_tx_lanes     : HDMI encoding + serializers + pins
// Port names follow AXI4-Stream conventions (s_axis_*) so Vivado's block
// design treats them as a stream interface clocked by s_axis_aclk.
// ----------------------------------------------------------------------
module video_sink (
    input  wire        s_axis_aclk,     // pixel clock (25.25 MHz)
    input  wire        clk_serial,      // 5x pixel clock
    input  wire        locked,          // MMCM lock (async)
    input  wire [1:0]  mode,            // filter select from the ARM (async)

    input  wire [15:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tuser,

    output wire        hdmi_tx_clk_p,
    output wire        hdmi_tx_clk_n,
    output wire [2:0]  hdmi_tx_p,
    output wire [2:0]  hdmi_tx_n,
    output wire        disp_frame_toggle,
    output wire        stream_locked
);

    (* ASYNC_REG = "TRUE" *) reg [1:0] rst_sync = 2'b11;
    always @(posedge s_axis_aclk or negedge locked) begin
        if (!locked) rst_sync <= 2'b11;
        else         rst_sync <= {rst_sync[0], 1'b0};
    end
    wire rst_pix = rst_sync[1];

    wire hsync, vsync, de;
    wire [9:0] pixel_x, pixel_y;
    video_timing_gen u_timing (
        .clk_pixel(s_axis_aclk), .rst(rst_pix),
        .hsync(hsync), .vsync(vsync), .data_enable(de),
        .pixel_x(pixel_x), .pixel_y(pixel_y)
    );

    wire hs_o, vs_o, de_o;
    wire [7:0] red, green, blue;
    axis_video_out #(.H_VIS(640), .V_VIS(480), .CNT_W(10)) u_vid (
        .clk_pixel(s_axis_aclk), .rst(rst_pix),
        .hsync_in(hsync), .vsync_in(vsync), .de_in(de),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .hsync_out(hs_o), .vsync_out(vs_o), .de_out(de_o),
        .red(red), .green(green), .blue(blue),
        .locked_to_stream(stream_locked)
    );

    (* ASYNC_REG = "TRUE" *) reg [1:0] mode_s0 = 2'b00, mode_s1 = 2'b00;
    always @(posedge s_axis_aclk) begin mode_s0 <= mode; mode_s1 <= mode_s0; end

    wire hs_f, vs_f, de_f;
    wire [7:0] red_f, green_f, blue_f;
    display_filter #(.WIDTH(640), .XW(10), .YW(9), .DELAY(802)) u_filt (
        .clk(s_axis_aclk), .mode(mode_s1),
        .hs_in(hs_o), .vs_in(vs_o), .de_in(de_o),
        .r_in(red), .g_in(green), .b_in(blue),
        .hs_out(hs_f), .vs_out(vs_f), .de_out(de_f),
        .r_out(red_f), .g_out(green_f), .b_out(blue_f)
    );

    tmds_tx_lanes #(.SYNC_ACTIVE_LOW(1)) u_tx (
        .clk_pixel(s_axis_aclk), .clk_serial(clk_serial), .rst(rst_pix),
        .red(red_f), .green(green_f), .blue(blue_f),
        .hsync(hs_f), .vsync(vs_f), .de(de_f),
        .tmds_clk_p(hdmi_tx_clk_p), .tmds_clk_n(hdmi_tx_clk_n),
        .tmds_d_p(hdmi_tx_p), .tmds_d_n(hdmi_tx_n)
    );

    reg frame_led = 1'b0, vs_d = 1'b0;
    always @(posedge s_axis_aclk) begin
        vs_d <= vsync;
        if (vsync && !vs_d) frame_led <= ~frame_led;
    end
    assign disp_frame_toggle = frame_led;
endmodule
