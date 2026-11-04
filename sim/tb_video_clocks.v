`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tb_video_clocks.v - checks the MMCM wrapper in Vivado xsim (needs unisim).
// Verifies: locked rises, pixel period ~39.6 ns, serial period ~7.92 ns,
// and the serial clock is exactly 5x the pixel clock (measured over 200
// pixel clocks, so a wrong divider would show up).
// ----------------------------------------------------------------------
module tb_video_clocks;
    reg clk_in = 0;
    reg rst = 1;
    wire clk_pixel, clk_serial, locked;
    integer errors = 0;

    always #4 clk_in = ~clk_in;    // 125 MHz

    video_clocks dut (.clk_in(clk_in), .rst(rst),
                  .clk_pixel(clk_pixel), .clk_serial(clk_serial),
                  .locked(locked));

    integer pix_edges, ser_edges;
    realtime t_start, t_end;
    integer i;

    initial begin
        #100 rst = 0;
        // wait for lock (with timeout)
        i = 0;
        while (!locked && i < 100000) begin #100; i = i + 1; end
        if (!locked) begin
            $display("FAIL: MMCM never locked");
            errors = errors + 1;
        end else begin
            // let outputs settle, then count edges over 200 pixel clocks
            repeat (20) @(posedge clk_pixel);
            pix_edges = 0; ser_edges = 0;
            @(posedge clk_pixel);
            t_start = $realtime;
            fork
                begin : count_pix
                    repeat (200) begin @(posedge clk_pixel); pix_edges = pix_edges + 1; end
                end
                begin : count_ser
                    forever begin @(posedge clk_serial); ser_edges = ser_edges + 1; end
                end
            join_any
            t_end = $realtime;
            disable count_ser;
            $display("pixel period  = %f ns (want ~39.60)", (t_end - t_start) / pix_edges);
            $display("serial edges per pixel clock = %f (want 5)", ser_edges * 1.0 / pix_edges);
            if (((t_end - t_start) / pix_edges) < 39.4 || ((t_end - t_start) / pix_edges) > 39.8) begin
                $display("FAIL: pixel period out of range"); errors = errors + 1;
            end
            if (ser_edges < 5 * pix_edges - 1 || ser_edges > 5 * pix_edges + 1) begin
                $display("FAIL: serial clock is not 5x pixel clock"); errors = errors + 1;
            end
        end
        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else             $display("=== %0d CHECK(S) FAILED ===", errors);
        $finish;
    end
endmodule
