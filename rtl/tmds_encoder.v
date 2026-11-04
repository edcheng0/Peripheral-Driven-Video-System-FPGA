`timescale 1ns / 1ps
//------------------------------------------------------------------------
// tmds_encoder.v
//
// TMDS = "Transition Minimized Differential Signaling" - this is the
// actual encoding scheme HDMI (and DVI) use on the wire. Plain 8-bit
// pixel data is NOT sent directly; instead, each 8-bit value is first
// converted into a 10-bit code with two important properties:
//
//   1. Transition minimization: reduces how often the signal has to
//      switch between 0 and 1, which reduces electrical noise/EMI at
//      high serial speeds.
//   2. DC balancing: over time, roughly equal numbers of 1s and 0s are
//      sent, which keeps the average voltage on the wire centered -
//      required for the receiver's electronics to work correctly.
//
// This module implements the standard two-stage algorithm from the
// DVI/HDMI specification: XOR/XNOR minimization, then a running-disparity
// balancer that remembers whether it's sent more 1s or 0s so far and
// compensates on the next pixel.
//
// One encoder instance is needed PER COLOR CHANNEL (so 3 total: red,
// green, blue) - each is independent except for control signals on the
// blue channel (which also carries hsync/vsync during blanking, per the
// HDMI spec).
//------------------------------------------------------------------------
module tmds_encoder (
    input  wire       clk,
    input  wire        rst,
    input  wire [7:0]  data_in,       // 8-bit pixel color value for this channel
    input  wire [1:0]  control_in,    // only meaningful on the "blue" channel instance: {vsync, hsync}
    input  wire        data_enable,   // high = visible pixel, low = blanking period
    output reg  [9:0]  tmds_out
);

    // ---- Stage 1: choose XOR or XNOR minimization ----
    // Implemented as functions + continuous assigns (not always @(*)):
    // an always @(*) block does not evaluate at time 0 unless an input
    // changes, which left q_m undefined (x) for the first pixel in
    // simulation. Continuous assigns always evaluate.
    function [3:0] count_ones8(input [7:0] v);
        integer k;
        begin
            count_ones8 = 0;
            for (k = 0; k < 8; k = k + 1)
                count_ones8 = count_ones8 + v[k];
        end
    endfunction

    function [8:0] minimize(input [7:0] d);
        reg [3:0] n1;
        integer k;
        begin
            n1 = count_ones8(d);
            minimize[0] = d[0];
            if ((n1 > 4) || (n1 == 4 && d[0] == 1'b0)) begin
                // XNOR chain, marker bit 0
                for (k = 1; k < 8; k = k + 1)
                    minimize[k] = minimize[k-1] ~^ d[k];
                minimize[8] = 1'b0;
            end else begin
                // XOR chain, marker bit 1
                for (k = 1; k < 8; k = k + 1)
                    minimize[k] = minimize[k-1] ^ d[k];
                minimize[8] = 1'b1;
            end
        end
    endfunction

    wire [8:0] q_m = minimize(data_in);   // 9-bit intermediate encoded value

    // ---- Stage 2: running disparity balancing ----
    // Signed running disparity ("Cnt" in the DVI 1.0 spec, section 3.3.3).
    // 6 bits signed gives headroom well beyond the spec's actual range.
    reg signed [5:0] disparity = 0;

    // bal = N1 - N0 = 2*N1 - 8 for q_m[7:0], kept explicitly signed to
    // avoid Verilog's unsigned-promotion trap in mixed arithmetic.
    wire [3:0]        q_m_ones = count_ones8(q_m[7:0]);
    wire signed [5:0] bal      = $signed({1'b0, q_m_ones, 1'b0}) - 6'sd8;

    wire signed [5:0] qm8_x2  = q_m[8] ? 6'sd2 : 6'sd0;   // 2 * q_m[8]
    wire signed [5:0] nqm8_x2 = q_m[8] ? 6'sd0 : 6'sd2;   // 2 * ~q_m[8]

    always @(posedge clk) begin
        if (rst) begin
            disparity <= 0;
            tmds_out  <= 10'b0;
        end else if (!data_enable) begin
            // ---- Blanking period: send one of 4 fixed, well-known
            // control codes instead of pixel data, encoding hsync/vsync ----
            case (control_in)
                2'b00: tmds_out <= 10'b1101010100;
                2'b01: tmds_out <= 10'b0010101011;
                2'b10: tmds_out <= 10'b0101010100;
                2'b11: tmds_out <= 10'b1010101011;
            endcase
            disparity <= 0; // control periods reset the running balance
        end else begin
            // ---- Visible period: encode actual pixel data ----
            // Follows the DVI 1.0 spec flowchart exactly. bit 9 of the
            // output tells the receiver "I inverted bits 7:0", bit 8 tells
            // it "XOR (1) or XNOR (0) was used".
            if (disparity == 0 || bal == 0) begin
                // Balanced so far, or this value is naturally balanced.
                // Spec: invert data bits exactly when q_m[8] == 0.
                tmds_out <= {~q_m[8], q_m[8], (q_m[8] ? q_m[7:0] : ~q_m[7:0])};
                if (q_m[8] == 1'b0)
                    disparity <= disparity - bal;   // Cnt + (N0 - N1)
                else
                    disparity <= disparity + bal;   // Cnt + (N1 - N0)
            end else if ((disparity > 0 && bal > 0) ||
                         (disparity < 0 && bal < 0)) begin
                // Already skewed toward the majority bit -> invert.
                tmds_out <= {1'b1, q_m[8], ~q_m[7:0]};
                disparity <= disparity + qm8_x2 - bal;   // Cnt + 2*q_m[8] + (N0 - N1)
            end else begin
                // Send as-is.
                tmds_out <= {1'b0, q_m[8], q_m[7:0]};
                disparity <= disparity - nqm8_x2 + bal;  // Cnt - 2*~q_m[8] + (N1 - N0)
            end
        end
    end

endmodule
