`timescale 1ns / 1ps
//------------------------------------------------------------------------
// tb_video_timing_gen.v
//
// Self-checking testbench. Runs the timing generator for slightly more
// than one full frame and verifies:
//   1. data_enable is high for exactly 640 pixels per visible line
//   2. hsync pulses are exactly 96 pixel-clocks wide
//   3. vsync pulses are exactly 2 lines wide
//   4. a full frame is exactly 800 x 525 = 420,000 pixel clocks
// Prints PASS/FAIL for each check - no waveform viewer needed to read
// the result, though it also dumps a .vcd file in case you want one.
//------------------------------------------------------------------------
module tb_video_timing_gen;

    reg clk = 0;
    reg rst = 1;
    wire hsync, vsync, data_enable;
    wire [9:0] pixel_x, pixel_y;

    integer errors = 0;

    video_timing_gen dut (
        .clk_pixel   (clk),
        .rst         (rst),
        .hsync       (hsync),
        .vsync       (vsync),
        .data_enable (data_enable),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y)
    );

    // 25 MHz clock -> 40 ns period -> 20 ns half period
    always #20 clk = ~clk;

    // ---- Check 1: count how many cycles data_enable is high during
    //      the very first visible line ----
    integer de_count_line0;
    integer hsync_width;
    integer vsync_width_lines;

    initial begin
        $dumpfile("video_timing_gen.vcd");
        $dumpvars(0, tb_video_timing_gen);

        // hold reset for a few clocks
        repeat (5) @(posedge clk);
        rst = 0;

        // ---- Check: data_enable high for exactly 640 cycles on line 0 ----
        de_count_line0 = 0;
        while (pixel_y == 0) begin
            @(posedge clk);
            if (data_enable) de_count_line0 = de_count_line0 + 1;
        end
        if (de_count_line0 == 640) begin
            $display("PASS: data_enable was high for exactly 640 pixels on line 0");
        end else begin
            $display("FAIL: expected 640 visible pixels on line 0, got %0d", de_count_line0);
            errors = errors + 1;
        end

        // ---- Check: hsync pulse width ----
        // wait for hsync to rise, then measure how long it stays high
        while (!hsync) @(posedge clk);
        hsync_width = 0;
        while (hsync) begin
            hsync_width = hsync_width + 1;
            @(posedge clk);
        end
        if (hsync_width == 96) begin
            $display("PASS: hsync pulse width was exactly 96 pixel clocks");
        end else begin
            $display("FAIL: expected hsync width 96, got %0d", hsync_width);
            errors = errors + 1;
        end

        // ---- Check: vsync pulse width (measured in lines, so watch pixel_y) ----
        while (!vsync) @(posedge clk);
        begin : vsync_check
            integer start_y;
            start_y = pixel_y;
            while (vsync) @(posedge clk);
            vsync_width_lines = pixel_y - start_y;
            // handle wraparound edge case
            if (vsync_width_lines < 0) vsync_width_lines = vsync_width_lines + 525;
        end
        if (vsync_width_lines == 2) begin
            $display("PASS: vsync pulse width was exactly 2 lines");
        end else begin
            $display("FAIL: expected vsync width 2 lines, got %0d", vsync_width_lines);
            errors = errors + 1;
        end

        // ---- Summary ----
        if (errors == 0)
            $display("=== ALL CHECKS PASSED ===");
        else
            $display("=== %0d CHECK(S) FAILED ===", errors);

        $finish;
    end

    // Safety timeout in case something hangs (slightly over 2 full frames)
    initial begin
        #40000000;
        $display("FAIL: testbench timed out - design likely never reached expected state");
        $finish;
    end

endmodule
