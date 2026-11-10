`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// cam_axis_src.v - the camera's pins in, an AXI4-Stream video source out.
// Thin wrapper: puts the camera's pixel clock on a global clock buffer (so
// it can clock the DMA stream) and instantiates cam_axis_bridge.
// Port names follow the AXI4-Stream naming convention so Vivado's block
// design recognises m_axis_* as a stream interface.
// ----------------------------------------------------------------------
module cam_axis_src (
    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_d,

    output wire        m_axis_aclk,     // the camera pixel clock, buffered
    output wire [15:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,   // unused: the camera cannot be paused
    output wire        m_axis_tlast,
    output wire        m_axis_tuser,
    output wire        frame_toggle,
    output wire [31:0] stat_a,          // {lines, href_clks}
    output wire [31:0] stat_b           // {drops, frames}
);
    BUFG u_bufg (.I(cam_pclk), .O(m_axis_aclk));

    wire [15:0] s_href, s_lines, s_drops, s_frames;
    cam_stats u_stats (
        .pclk(m_axis_aclk), .vsync(cam_vsync), .href(cam_href),
        .tvalid(m_axis_tvalid), .tready(m_axis_tready),
        .href_clks(s_href), .lines(s_lines), .drops(s_drops), .frames(s_frames)
    );
    assign stat_a = {s_lines, s_href};
    assign stat_b = {s_drops, s_frames};

    cam_axis_bridge #(.WIDTH(640), .HEIGHT(480), .XW(10), .YW(9)) u_bridge (
        .pclk(m_axis_aclk), .vsync(cam_vsync), .href(cam_href), .d(cam_d),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast), .m_axis_tuser(m_axis_tuser),
        .frame_toggle(frame_toggle)
    );
endmodule
