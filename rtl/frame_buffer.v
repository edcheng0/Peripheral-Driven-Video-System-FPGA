`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// frame_buffer.v - a memory with two independent clocks.
//
// WHY: the camera delivers pixels at its own pace (PCLK domain) while the
// HDMI output asks for pixels at a different, unrelated pace (pixel-clock
// domain). Two clocks that aren't related are called different "clock
// domains"; passing data between them directly is unsafe. A dual-clock
// RAM is the standard safe bridge: one side only writes (clock wclk), the
// other side only reads (clock rclk), and they never touch the same flops.
//
// Zynq-7020 has ~4.9 Mb of block RAM. A 320x240 RGB565 frame is 1.23 Mb,
// so it fits (about 35 of 140 BRAM36 blocks).
//
// Read is SYNCHRONOUS: the data for raddr shows up one rclk cycle later
// (that is what lets Vivado map this onto block RAM).
//
// Note: reading a location while it is being written (same address, two
// clocks) can return old or new data - for a video frame that just means
// a pixel from the previous or current frame, which is harmless.
// ----------------------------------------------------------------------
module frame_buffer #(
    parameter DATA_W = 16,
    parameter DEPTH  = 76800,                // 320 x 240
    parameter ADDR_W = $clog2(DEPTH)
) (
    input  wire              wclk,
    input  wire              we,
    input  wire [ADDR_W-1:0] waddr,
    input  wire [DATA_W-1:0] wdata,

    input  wire              rclk,
    input  wire [ADDR_W-1:0] raddr,
    output reg  [DATA_W-1:0] rdata
);

    (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:DEPTH-1];

    always @(posedge wclk)
        if (we) mem[waddr] <= wdata;

    always @(posedge rclk)
        rdata <= mem[raddr];

endmodule
