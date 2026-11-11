`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// servo_ctrl.v - servo_pwm with the position input made safe to drive from
// another clock domain (the ARM's GPIO). The position is a slow-changing
// 8-bit number, so it is simply passed through two flip-flops first.
// ----------------------------------------------------------------------
module servo_ctrl #(
    parameter integer CLK_HZ = 125_000_000
) (
    input  wire       clk,
    input  wire [7:0] position,    // asynchronous to clk
    output wire       pwm
);
    (* ASYNC_REG = "TRUE" *) reg [7:0] pos_s0 = 8'd128, pos_s1 = 8'd128;
    always @(posedge clk) begin
        pos_s0 <= position;
        pos_s1 <= pos_s0;
    end
    servo_pwm #(.CLK_HZ(CLK_HZ)) u_pwm (.clk(clk), .rst(1'b0), .position(pos_s1), .pwm(pwm));
endmodule
