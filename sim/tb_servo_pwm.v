`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tb_servo_pwm.v - measures the real output: period must be 20 ms and
// the high time must be 1 ms + position/256 ms, for several positions,
// including a position change in the middle of a period (must not alter
// that period's pulse). Uses a 1 MHz clock so 1 ms = 1000 clocks.
// ----------------------------------------------------------------------
module tb_servo_pwm;
    reg clk = 0, rst = 1;
    reg [7:0] position = 0;
    wire pwm;
    integer errors = 0;
    always #500 clk = ~clk;
    servo_pwm #(.CLK_HZ(1_000_000)) dut (.clk(clk), .rst(rst), .position(position), .pwm(pwm));

    integer hi, per, last_rise, n;
    reg pwm_d = 0;
    integer widths [0:7];
    integer periods [0:7];
    integer nr = 0;
    integer high_cnt = 0;
    always @(posedge clk) begin
        pwm_d <= pwm;
        if (pwm) high_cnt = high_cnt + 1;
        if (pwm && !pwm_d) begin   // rising edge
            if (nr > 0) periods[nr-1] = $time/1000 - last_rise;
            last_rise = $time/1000;
            high_cnt = 1;
        end
        if (!pwm && pwm_d && nr < 8) begin
            widths[nr] = high_cnt;
            nr = nr + 1;
        end
    end

    task expect_w(input integer idx, input integer want);
        begin
            if (widths[idx] < want - 1 || widths[idx] > want + 1) begin
                errors = errors + 1;
                $display("FAIL: pulse %0d width %0d clocks, want %0d", idx, widths[idx], want);
            end
        end
    endtask

    integer i;
    initial begin
        repeat (3) @(negedge clk); rst = 0;
        position = 8'd0;
        wait (nr >= 2);              // pulses 0,1 use position 0 (pulse 0 is the reset default 1 ms)
        position = 8'd128;
        wait (nr >= 4);
        position = 8'd255;
        wait (nr >= 6);
        // change just after a pulse ended, mid-period: next pulse must NOT change until the period boundary
        wait (nr >= 7);
        expect_w(1, 1000);
        expect_w(3, 1500);           // 128 -> 1000 + 128*1000/256 = 1500 (pulse 2 may still be old)
        expect_w(5, 1996);           // 255 -> 1000 + 255*1000/256
        for (i = 0; i < 5; i = i + 1)
            if (periods[i] < 19999 || periods[i] > 20001) begin
                errors = errors + 1; $display("FAIL: period %0d = %0d clocks, want 20000", i, periods[i]);
            end
        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else             $display("=== %0d CHECK(S) FAILED ===", errors);
        $finish;
    end
    initial begin #2_000_000_000; $display("FAIL: timeout"); $finish; end
endmodule
