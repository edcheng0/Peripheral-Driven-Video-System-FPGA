`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// cam_axis_bridge.v - camera pixels -> an AXI4-Stream video stream.
//
// WHAT IS AXI4-STREAM VIDEO? A simple way to pass pixels between blocks:
//   tdata  : one pixel (here 16 bits of RGB565)
//   tvalid : "this beat holds a real pixel"
//   tlast  : "this is the LAST pixel of the line"
//   tuser  : "this is the FIRST pixel of the frame" (start of frame)
// The Xilinx video DMA (VDMA) accepts exactly this and writes the frame
// into DDR3 memory.
//
// The camera cannot be paused, so there is no back-pressure here: the DMA's
// internal FIFO has to keep up (it does; the data rate is tiny).
//
// Everything is in the camera's pixel-clock domain (pclk).
// ----------------------------------------------------------------------
module cam_axis_bridge #(
    parameter WIDTH  = 640,
    parameter HEIGHT = 480,
    parameter XW     = 10,     // must be able to hold the value WIDTH
    parameter YW     = 9       // must hold HEIGHT-1
) (
    input  wire        pclk,
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  d,

    output reg  [15:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,
    output reg         m_axis_tuser,
    output reg         frame_toggle     // flips once per camera frame (for an LED)
);

    wire          pv;
    wire [XW-1:0] px;
    wire [YW-1:0] py;
    wire [15:0]   pd;
    wire          fstart;

    ov7670_capture #(.WIDTH(WIDTH), .HEIGHT(HEIGHT), .XW(XW), .YW(YW)) u_cap (
        .pclk(pclk), .vsync(vsync), .href(href), .d(d),
        .pix_valid(pv), .pix_x(px), .pix_y(py), .pix_data(pd), .frame_start(fstart)
    );

    initial begin
        m_axis_tdata  = 16'd0;
        m_axis_tvalid = 1'b0;
        m_axis_tlast  = 1'b0;
        m_axis_tuser  = 1'b0;
        frame_toggle  = 1'b0;
    end

    always @(posedge pclk) begin
        m_axis_tvalid <= pv;
        m_axis_tdata  <= pd;
        m_axis_tlast  <= (px == WIDTH - 1);
        m_axis_tuser  <= (px == 0) && (py == 0);
        if (fstart) frame_toggle <= ~frame_toggle;
    end

endmodule
