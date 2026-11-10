`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// axis_video_out.v - AXI4-Stream video in, display pixels out.
//
// The video DMA reads frames out of DDR3 memory and hands them to us as a
// stream of RGB565 pixels (see cam_axis_bridge.v for the signal meanings).
// The display has its own rhythm: video_timing_gen says exactly when each
// pixel is wanted. This block lines the two up:
//
//   DRAIN : not lined up yet. Throw stream beats away until the first pixel
//           of a frame (tuser) shows up at the head of the stream.
//   ARMED : that first pixel is waiting. Hold it (tready = 0) until the
//           display reaches pixel (0,0), then start.
//   RUN   : take one stream beat on every visible pixel.
//
// If anything goes wrong (the stream runs dry, or a line ends at the wrong
// place) we go back to DRAIN and re-lock on the next frame; the picture
// glitches for at most a frame or two instead of staying shifted forever.
//
// Output is registered, so the sync/enable signals are delayed by one clock
// to stay lined up with the color.
// ----------------------------------------------------------------------
module axis_video_out #(
    parameter H_VIS  = 640,
    parameter V_VIS  = 480,
    parameter CNT_W  = 10
) (
    input  wire              clk_pixel,
    input  wire              rst,

    // from video_timing_gen
    input  wire              hsync_in,
    input  wire              vsync_in,
    input  wire              de_in,
    input  wire [CNT_W-1:0]  pixel_x,
    input  wire [CNT_W-1:0]  pixel_y,

    // AXI4-Stream video in (RGB565)
    input  wire [15:0]       s_axis_tdata,
    input  wire              s_axis_tvalid,
    output reg               s_axis_tready,
    input  wire              s_axis_tlast,
    input  wire              s_axis_tuser,

    output reg               hsync_out,
    output reg               vsync_out,
    output reg               de_out,
    output wire [7:0]        red,
    output wire [7:0]        green,
    output wire [7:0]        blue,
    output wire              locked_to_stream   // 1 while in RUN or ARMED
);

    localparam [1:0] DRAIN = 2'd0, ARMED = 2'd1, RUN = 2'd2;
    reg [1:0] state = DRAIN;

    wire first_px = de_in && (pixel_x == 0) && (pixel_y == 0);
    wire last_px  = de_in && (pixel_x == H_VIS - 1) && (pixel_y == V_VIS - 1);
    wire eol      = (pixel_x == H_VIS - 1);

    // one beat is accepted on every clock where tvalid and tready are both 1
    always @(*) begin
        case (state)
            DRAIN:   s_axis_tready = ~(s_axis_tvalid & s_axis_tuser);
            ARMED:   s_axis_tready = first_px;
            default: s_axis_tready = de_in;
        endcase
    end

    reg [15:0] pix = 16'd0;

    always @(posedge clk_pixel) begin
        hsync_out <= hsync_in;
        vsync_out <= vsync_in;
        de_out    <= de_in;

        if (rst) begin
            state <= DRAIN;
            pix   <= 16'd0;
        end else begin
            case (state)
                DRAIN: begin
                    pix <= 16'd0;
                    if (s_axis_tvalid && s_axis_tuser) state <= ARMED;
                end

                ARMED: begin
                    pix <= 16'd0;
                    if (first_px) begin
                        pix   <= s_axis_tdata;
                        state <= RUN;
                    end
                end

                default: begin    // RUN
                    if (!de_in) begin
                        pix <= 16'd0;
                    end else if (!s_axis_tvalid) begin
                        pix   <= 16'd0;        // stream ran dry: lose lock
                        state <= DRAIN;
                    end else begin
                        pix <= s_axis_tdata;
                        if (s_axis_tlast != eol) state <= DRAIN;   // line length mismatch
                        else if (last_px)        state <= DRAIN;   // frame finished normally
                    end
                end
            endcase
        end
    end

    // RGB565 -> RGB888 by copying the top bits into the low bits
    assign red   = {pix[15:11], pix[15:13]};
    assign green = {pix[10:5],  pix[10:9]};
    assign blue  = {pix[4:0],   pix[4:2]};

    assign locked_to_stream = (state != DRAIN);

endmodule
