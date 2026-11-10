`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// cam_stats.v - measures what the camera and the video DMA are doing, so the
// ARM can print it (debug aid). All counters run on the camera pixel clock.
//   href_clks : clocks HREF was high in the last full line (640 px = 1280)
//   lines     : HREF pulses (lines) in the last full frame   (expect 480)
//   drops     : beats the DMA refused (tvalid high, tready low), saturating
//   frames    : frames seen (VSYNC pulses), wraps
// The ARM reads these as slow-changing numbers.
// ----------------------------------------------------------------------
module cam_stats (
    input  wire        pclk,
    input  wire        vsync,
    input  wire        href,
    input  wire        tvalid,
    input  wire        tready,
    output reg  [15:0] href_clks = 16'd0,
    output reg  [15:0] lines     = 16'd0,
    output reg  [15:0] drops     = 16'd0,
    output reg  [15:0] frames    = 16'd0
);
    reg vs_d = 1'b0, hr_d = 1'b0;
    reg [15:0] hcnt = 16'd0, lcnt = 16'd0;
    always @(posedge pclk) begin
        vs_d <= vsync; hr_d <= href;
        if (href) hcnt <= hcnt + 1'b1;
        if (!href && hr_d) begin href_clks <= hcnt; hcnt <= 16'd0; end
        if (href && !hr_d) lcnt <= lcnt + 1'b1;
        if (vsync && !vs_d) begin lines <= lcnt; lcnt <= 16'd0; frames <= frames + 1'b1; end
        if (tvalid && !tready && drops != 16'hFFFF) drops <= drops + 1'b1;
    end
endmodule
