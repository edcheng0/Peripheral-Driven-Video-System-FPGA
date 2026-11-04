`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// cam_to_display.v - camera pixels in, display pixels out (no pins, no
// Xilinx primitives, so it can be simulated with plain Verilog).
//
//   CAMERA SIDE (clock = cam_pclk)            DISPLAY SIDE (clock = clk_pixel)
//   ov7670_capture -> mode mux ----> frame_buffer ----> pixel_reader
//                      |                (dual-clock RAM)
//             raw / gray / sobel / invert
//
// `mode` (switches, asynchronous) selects what is STORED:
//    0 = raw color            1 = grayscale
//    2 = Sobel edges (gray)   3 = inverted color
// Filtering on the write side is convenient: pixels arrive in clean
// raster order there, which the Sobel line buffers need.
//
// Clock-domain crossings (CDC):
//   * mode: 2-flop synchronizer into cam_pclk (it is a quasi-static level).
//   * pixels: through the dual-clock frame_buffer (the only safe path).
// The picture can "tear" (top from the new frame, bottom from the old one)
// because writer and reader are not frame-synchronised. Fine for now.
//
// SRC_W x SRC_H is the stored size; display is that << SHIFT.
// Sobel mode only writes the interior pixels (border keeps old content).
// ----------------------------------------------------------------------
module cam_to_display #(
    parameter SRC_W = 320,
    parameter SRC_H = 240,
    parameter XW    = 9,      // must be able to hold the value SRC_W
    parameter YW    = 8,      // must hold SRC_H-1
    parameter SHIFT = 1,
    parameter CNT_W = 10
) (
    // camera
    input  wire          cam_pclk,
    input  wire          cam_vsync,
    input  wire          cam_href,
    input  wire [7:0]    cam_d,
    input  wire [1:0]    mode,            // async, from switches

    // display timing (clk_pixel domain)
    input  wire              clk_pixel,
    input  wire              hsync_in,
    input  wire              vsync_in,
    input  wire              de_in,
    input  wire [CNT_W-1:0]  pixel_x,
    input  wire [CNT_W-1:0]  pixel_y,

    output wire              hsync_out,
    output wire              vsync_out,
    output wire              de_out,
    output wire [7:0]        red,
    output wire [7:0]        green,
    output wire [7:0]        blue
);

    localparam DEPTH  = SRC_W * SRC_H;
    localparam ADDR_W = $clog2(DEPTH);

    // ---- mode -> camera clock domain ----
    (* ASYNC_REG = "TRUE" *) reg [1:0] mode_s0 = 2'b00, mode_s1 = 2'b00;
    always @(posedge cam_pclk) begin
        mode_s0 <= mode;
        mode_s1 <= mode_s0;
    end

    // ---- capture ----
    wire          pv;
    wire [XW-1:0] px;
    wire [YW-1:0] py;
    wire [15:0]   pd;
    wire          fstart;
    ov7670_capture #(.WIDTH(SRC_W), .HEIGHT(SRC_H), .XW(XW), .YW(YW)) u_cap (
        .pclk(cam_pclk), .vsync(cam_vsync), .href(cam_href), .d(cam_d),
        .pix_valid(pv), .pix_x(px), .pix_y(py), .pix_data(pd), .frame_start(fstart)
    );

    // ---- filters ----
    wire [7:0] gray;
    rgb565_to_gray u_gray (.rgb565(pd), .gray(gray));

    wire          sob_valid;
    wire [XW-1:0] sob_x;
    wire [YW-1:0] sob_y;
    wire [7:0]    sob_mag;
    sobel_3x3 #(.WIDTH(SRC_W), .XW(XW), .YW(YW)) u_sobel (
        .clk(cam_pclk), .sof(fstart), .in_valid(pv), .in_pixel(gray),
        .out_valid(sob_valid), .out_x(sob_x), .out_y(sob_y), .out_mag(sob_mag)
    );

    // gray value -> RGB565 with equal R, G, B
    function [15:0] gray565(input [7:0] g);
        gray565 = {g[7:3], g[7:2], g[7:3]};
    endfunction

    // ---- mode mux (registered: one stage before the RAM) ----
    reg                wr_en   = 1'b0;
    reg  [XW-1:0]      wr_x    = 0;
    reg  [YW-1:0]      wr_y    = 0;
    reg  [15:0]        wr_data = 16'd0;
    always @(posedge cam_pclk) begin
        case (mode_s1)
            2'd0: begin wr_en <= pv;        wr_x <= px;    wr_y <= py;    wr_data <= pd;               end
            2'd1: begin wr_en <= pv;        wr_x <= px;    wr_y <= py;    wr_data <= gray565(gray);    end
            2'd2: begin wr_en <= sob_valid; wr_x <= sob_x; wr_y <= sob_y; wr_data <= gray565(sob_mag); end
            default: begin wr_en <= pv;     wr_x <= px;    wr_y <= py;    wr_data <= ~pd;              end
        endcase
    end

    wire [ADDR_W-1:0] wr_addr = wr_y * SRC_W + wr_x;

    // ---- frame buffer ----
    wire [ADDR_W-1:0] rd_addr;
    wire [15:0]       rd_data;
    frame_buffer #(.DATA_W(16), .DEPTH(DEPTH)) u_fb (
        .wclk(cam_pclk), .we(wr_en), .waddr(wr_addr), .wdata(wr_data),
        .rclk(clk_pixel), .raddr(rd_addr), .rdata(rd_data)
    );

    // ---- display read ----
    pixel_reader #(.SRC_W(SRC_W), .SRC_H(SRC_H), .SHIFT(SHIFT), .CNT_W(CNT_W)) u_rd (
        .clk_pixel(clk_pixel),
        .hsync_in(hsync_in), .vsync_in(vsync_in), .de_in(de_in),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .addr(rd_addr), .rdata(rd_data),
        .hsync_out(hsync_out), .vsync_out(vsync_out), .de_out(de_out),
        .red(red), .green(green), .blue(blue)
    );

endmodule
