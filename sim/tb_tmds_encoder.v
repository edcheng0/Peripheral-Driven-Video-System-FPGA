`timescale 1ns / 1ps
//------------------------------------------------------------------------
// tb_tmds_encoder.v
//
// Two kinds of checks:
//   1. The 4 fixed control codes come out exactly as specified during
//      blanking (these are hardcoded constants in the HDMI/DVI spec,
//      so this is a simple exact-match check).
//   2. The DC-balancing property: over a long run of many different
//      pixel values, the internal disparity counter should never grow
//      without bound. If it does, that's a real bug (it would mean
//      the transmitted signal isn't DC-balanced, which breaks real
//      HDMI receivers even though a plain simulation wouldn't "look"
//      wrong).
//------------------------------------------------------------------------
module tb_tmds_encoder;

    reg clk = 0;
    reg rst = 1;
    reg [7:0] data_in = 0;
    reg [1:0] control_in = 0;
    reg data_enable = 0;
    wire [9:0] tmds_out;

    integer errors = 0;
    integer i;
    integer ones_seen, zeros_seen;
    integer decode_errors = 0;
    integer running_cnt = 0;   // (1s - 0s) over all 10 bits actually sent
    integer max_abs_cnt = 0;

    // Reference TMDS decoder - what a real HDMI/DVI receiver does.
    // If encode->decode doesn't round-trip, a monitor shows wrong colors.
    function [7:0] tmds_decode(input [9:0] w);
        reg [7:0] d;
        integer k;
        begin
            d = w[9] ? ~w[7:0] : w[7:0];   // undo inversion
            tmds_decode[0] = d[0];
            for (k = 1; k < 8; k = k + 1)
                tmds_decode[k] = w[8] ? (d[k] ^ d[k-1]) : ~(d[k] ^ d[k-1]);
        end
    endfunction

    tmds_encoder dut (
        .clk         (clk),
        .rst         (rst),
        .data_in     (data_in),
        .control_in  (control_in),
        .data_enable (data_enable),
        .tmds_out    (tmds_out)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // ---- Check 1: control codes during blanking ----
        data_enable = 0;

        control_in = 2'b00; @(posedge clk); #1;
        if (tmds_out === 10'b1101010100)
            $display("PASS: control code 00 correct");
        else begin
            $display("FAIL: control code 00 got %b", tmds_out);
            errors = errors + 1;
        end

        control_in = 2'b01; @(posedge clk); #1;
        if (tmds_out === 10'b0010101011)
            $display("PASS: control code 01 correct");
        else begin
            $display("FAIL: control code 01 got %b", tmds_out);
            errors = errors + 1;
        end

        control_in = 2'b10; @(posedge clk); #1;
        if (tmds_out === 10'b0101010100)
            $display("PASS: control code 10 correct");
        else begin
            $display("FAIL: control code 10 got %b", tmds_out);
            errors = errors + 1;
        end

        control_in = 2'b11; @(posedge clk); #1;
        if (tmds_out === 10'b1010101011)
            $display("PASS: control code 11 correct");
        else begin
            $display("FAIL: control code 11 got %b", tmds_out);
            errors = errors + 1;
        end

        // ---- Check 2: DC balance over many pixels ----
        // Feed a long, varied sequence of pixel values and confirm the
        // OVERALL count of 1s vs 0s sent stays close to 50/50 - this is
        // the real-world consequence of correct disparity balancing.
        data_enable = 1;
        ones_seen  = 0;
        zeros_seen = 0;

        // First 256 iterations sweep EVERY possible byte value; the rest
        // are a varied pseudo-random pattern.
        for (i = 0; i < 2256; i = i + 1) begin
            data_in = (i < 256) ? i : ((i * 37 + 13) % 256);
            @(posedge clk); #1;
            ones_seen  = ones_seen  + $countones(tmds_out[7:0]); // count the 8 data bits, exclude the 2 mode/disparity flag bits
            zeros_seen = zeros_seen + (8 - $countones(tmds_out[7:0]));

            // Round-trip: the receiver must recover the exact pixel byte.
            if (tmds_decode(tmds_out) !== data_in) begin
                if (decode_errors < 5)
                    $display("FAIL: data_in=%h -> tmds=%b decodes to %h",
                              data_in, tmds_out, tmds_decode(tmds_out));
                decode_errors = decode_errors + 1;
            end

            // Running (1s - 0s) over all 10 transmitted bits must stay bounded.
            running_cnt = running_cnt + 2 * $countones(tmds_out) - 10;
            if (running_cnt > max_abs_cnt)  max_abs_cnt = running_cnt;
            if (-running_cnt > max_abs_cnt) max_abs_cnt = -running_cnt;
        end

        if (decode_errors == 0)
            $display("PASS: all pixels round-trip through a reference TMDS decoder");
        else begin
            $display("FAIL: %0d pixels did not decode back correctly", decode_errors);
            errors = errors + 1;
        end

        if (max_abs_cnt <= 20)
            $display("PASS: running disparity stayed bounded (max |1s-0s| = %0d)", max_abs_cnt);
        else begin
            $display("FAIL: running disparity drifted to %0d - DC balance broken", max_abs_cnt);
            errors = errors + 1;
        end

        $display("Over 2256 pixels: %0d ones, %0d zeros (out of %0d total data bits)",
                  ones_seen, zeros_seen, ones_seen + zeros_seen);

        // A healthy DC-balanced encoder should land close to 50/50 -
        // allow a generous +/-5% tolerance since this is a deterministic
        // test pattern, not true random data.
        if (ones_seen > (ones_seen + zeros_seen) * 45 / 100 &&
            ones_seen < (ones_seen + zeros_seen) * 55 / 100) begin
            $display("PASS: output stayed DC-balanced within tolerance");
        end else begin
            $display("FAIL: output was NOT DC-balanced - check disparity logic");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("=== ALL CHECKS PASSED ===");
        else
            $display("=== %0d CHECK(S) FAILED ===", errors);

        $finish;
    end

endmodule
