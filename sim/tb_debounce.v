`timescale 1ns / 1ps
//------------------------------------------------------------------------
// tb_debounce.v
//
// Uses a short debounce window (100 clocks instead of the real design's
// ~500,000) purely so the simulation runs fast - the logic being tested
// is identical either way, only the constant changes.
//------------------------------------------------------------------------
module tb_debounce;

    reg clk = 0;
    reg rst = 1;
    reg noisy = 0;
    wire clean;
    integer errors = 0;

    debounce #(.DEBOUNCE_CYCLES(100)) dut (
        .clk       (clk),
        .rst       (rst),
        .noisy_in  (noisy),
        .clean_out (clean)
    );

    always #5 clk = ~clk; // 100 MHz-equivalent for this test

    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (4) @(posedge clk);

        // ---- Test 1: a brief glitch (shorter than the debounce window)
        //      should NOT affect the output ----
        noisy = 1;
        repeat (10) @(posedge clk);   // way less than 100-cycle window
        noisy = 0;
        repeat (10) @(posedge clk);
        if (clean == 0)
            $display("PASS: short glitch was correctly ignored");
        else begin
            $display("FAIL: short glitch incorrectly passed through");
            errors = errors + 1;
        end

        // ---- Test 2: a sustained change (longer than the debounce
        //      window) SHOULD eventually appear on the output ----
        noisy = 1;
        repeat (150) @(posedge clk);  // more than the 100-cycle window
        if (clean == 1)
            $display("PASS: sustained press correctly passed through after debounce window");
        else begin
            $display("FAIL: sustained press did not register");
            errors = errors + 1;
        end

        // ---- Test 3: releasing should also debounce the same way ----
        noisy = 0;
        repeat (150) @(posedge clk);
        if (clean == 0)
            $display("PASS: sustained release correctly passed through after debounce window");
        else begin
            $display("FAIL: sustained release did not register");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("=== ALL CHECKS PASSED ===");
        else
            $display("=== %0d CHECK(S) FAILED ===", errors);

        $finish;
    end

endmodule
