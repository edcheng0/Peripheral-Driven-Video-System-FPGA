`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tb_servo_ctrl.v - checks servo_ctrl turns a position into the right pulse
// width (1 ms + position/256 * 1 ms), measured with a scaled-down clock
// (CLK_HZ = 50 kHz: 1 ms = 50 clocks, 20 ms = 1000 clocks).
// ----------------------------------------------------------------------
module tb_servo_ctrl;
    localparam CLK_HZ = 50_000;
    integer errors = 0;
    reg clk = 0;
    always #10 clk = ~clk;
    reg [7:0] position = 8'd0;
    wire pwm;
    servo_ctrl #(.CLK_HZ(CLK_HZ)) dut (.clk(clk), .position(position), .pwm(pwm));

    // measure every high pulse
    integer width = 0, last_width = 0, pulses = 0;
    reg pwm_d = 0;
    always @(posedge clk) begin
        pwm_d <= pwm;
        if (pwm) width <= width + 1;
        if (!pwm && pwm_d) begin last_width <= width; width <= 0; pulses <= pulses + 1; end
    end

    task check(input [7:0] pos);
        integer want, p0;
        begin
            position = pos;
            repeat (3 * 1000) @(posedge clk);          // let it take effect and settle
            p0 = pulses;
            wait (pulses > p0);                         // next complete pulse
            @(posedge clk);
            want = 50 + ((pos * 50) >> 8);
            if (last_width !== want) begin
                errors = errors + 1;
                $display("position %0d: pulse %0d clocks, expected %0d", pos, last_width, want);
            end else $display("position %0d: pulse %0d clocks OK", pos, last_width);
        end
    endtask

    initial begin
        check(8'd0); check(8'd128); check(8'd255); check(8'd37);
        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else $display("=== %0d ERRORS ===", errors);
        $finish;
    end
endmodule
