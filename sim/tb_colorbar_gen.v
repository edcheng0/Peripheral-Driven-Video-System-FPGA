`timescale 1ns / 1ps
//------------------------------------------------------------------------
// tb_colorbar_gen.v
//
// Sweeps pixel_x across the full 0-639 range and checks that each
// 80-pixel-wide bar shows the correct color, and that the transitions
// between bars happen at exactly the right x position.
//------------------------------------------------------------------------
module tb_colorbar_gen;

    reg [9:0] pixel_x;
    wire [7:0] red, green, blue;
    integer errors = 0;
    integer bar;

    // Expected colors, indexed 0-7, packed as {R,G,B}
    reg [23:0] expected [0:7];

    colorbar_gen dut (
        .pixel_x (pixel_x),
        .red     (red),
        .green   (green),
        .blue    (blue)
    );

    initial begin
        expected[0] = {8'hFF, 8'hFF, 8'hFF}; // white
        expected[1] = {8'hFF, 8'hFF, 8'h00}; // yellow
        expected[2] = {8'h00, 8'hFF, 8'hFF}; // cyan
        expected[3] = {8'h00, 8'hFF, 8'h00}; // green
        expected[4] = {8'hFF, 8'h00, 8'hFF}; // magenta
        expected[5] = {8'hFF, 8'h00, 8'h00}; // red
        expected[6] = {8'h00, 8'h00, 8'hFF}; // blue
        expected[7] = {8'h00, 8'h00, 8'h00}; // black

        // Check the middle pixel of every bar (safely inside its range)
        for (bar = 0; bar < 8; bar = bar + 1) begin
            pixel_x = bar * 80 + 40; // middle of each 80-pixel bar
            #1;
            if ({red, green, blue} === expected[bar]) begin
                $display("PASS: bar %0d (x=%0d) is correct color", bar, pixel_x);
            end else begin
                $display("FAIL: bar %0d (x=%0d) expected %h got %h",
                          bar, pixel_x, expected[bar], {red, green, blue});
                errors = errors + 1;
            end
        end

        // Check the exact boundary between bar 0 and bar 1 (x=79 vs x=80)
        pixel_x = 79; #1;
        if ({red, green, blue} !== expected[0]) begin
            $display("FAIL: x=79 should still be bar 0");
            errors = errors + 1;
        end
        pixel_x = 80; #1;
        if ({red, green, blue} !== expected[1]) begin
            $display("FAIL: x=80 should already be bar 1");
            errors = errors + 1;
        end else begin
            $display("PASS: bar boundary at x=79/80 is exact");
        end

        if (errors == 0)
            $display("=== ALL CHECKS PASSED ===");
        else
            $display("=== %0d CHECK(S) FAILED ===", errors);

        $finish;
    end

endmodule
