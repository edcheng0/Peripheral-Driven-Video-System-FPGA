`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tb_tmds_serializer.v - Vivado xsim testbench (needs unisim).
// Sends a known sequence of 64 different 10-bit words, records the output
// bit on every edge of the serial clock, then checks that:
//   1. the recorded stream contains the words back-to-back, in order,
//      least-significant bit first (unknown startup latency is found by
//      searching, but once found, 40 consecutive words must match exactly)
//   2. out_n is always the exact opposite of out_p
// ----------------------------------------------------------------------
module tb_tmds_serializer;
    reg clk_pixel = 0, clk_serial = 0, rst = 1;
    reg [9:0] data = 0;
    wire out_p, out_n;
    integer errors = 0;

    // 25 MHz pixel / 125 MHz serial (exact 5x), edges start aligned
    always #20 clk_pixel  = ~clk_pixel;
    always #4  clk_serial = ~clk_serial;

    tmds_serializer dut (.clk_pixel(clk_pixel), .clk_serial(clk_serial),
                         .rst(rst), .data(data), .out_p(out_p), .out_n(out_n));

    // 64 distinct, unsymmetric words
    function [9:0] word(input integer i);
        word = (((i % 64) * 211) + 37) & 10'h3FF;
    endfunction

    // send words on the falling edge of the pixel clock
    integer widx = 0;
    always @(negedge clk_pixel) begin
        data <= word(widx);
        widx <= widx + 1;
    end

    // record the pin twice per serial cycle, 2 ns after each edge
    localparam NBITS = 4000;
    reg stream [0:NBITS-1];
    integer nb = 0;
    always @(clk_serial) begin
        #2;
        if (!rst && nb < NBITS) begin
            stream[nb] = out_p;
            nb = nb + 1;
        end
        if (out_p === out_n && !rst) begin
            errors = errors + 1;
            $display("FAIL: out_p and out_n not opposite at %0t", $time);
        end
    end

    function [9:0] chunk(input integer start);
        integer b;
        begin
            for (b = 0; b < 10; b = b + 1) chunk[b] = stream[start + b];
        end
    endfunction

    integer o, j, k, found, ok;
    initial begin
        repeat (6) @(negedge clk_pixel);
        rst = 0;
        wait (nb >= NBITS);
        found = 0;
        // search for where word(j) starts in the stream, then check 40 in a row
        for (o = 40; o < 200 && !found; o = o + 1) begin
            for (j = 0; j < 64 && !found; j = j + 1) begin
                ok = 1;
                for (k = 0; k < 40; k = k + 1)
                    if (chunk(o + 10*k) !== word(j + k)) ok = 0;
                if (ok) begin
                    found = 1;
                    $display("Aligned: stream bit %0d = bit 0 of word %0d", o, j);
                end
            end
        end
        if (!found) begin
            $display("FAIL: sent words never appeared, in order and LSB-first, in the output");
            errors = errors + 1;
        end
        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else             $display("=== %0d CHECK(S) FAILED ===", errors);
        $finish;
    end
endmodule
