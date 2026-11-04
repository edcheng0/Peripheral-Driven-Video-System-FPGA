`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// servo_pwm.v - drives a hobby servo from an 8-bit position.
//
// A hobby servo wants a pulse every 20 ms (50 Hz). The pulse WIDTH is the
// command: 1.0 ms = one end of travel, 1.5 ms = centre, 2.0 ms = other end.
//   width = 1 ms + position/256 * 1 ms        (position 0..255)
// Position changes take effect at the start of the next 20 ms period, so
// the pulse is never cut short or stretched mid-way.
// ----------------------------------------------------------------------
module servo_pwm #(
    parameter integer CLK_HZ = 125_000_000
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] position,
    output reg        pwm
);
    localparam integer PERIOD_CYC = CLK_HZ / 50;       // 20 ms
    localparam integer MIN_CYC    = CLK_HZ / 1000;     // 1 ms
    localparam integer RANGE_CYC  = CLK_HZ / 1000;     // +1 ms at full scale
    localparam integer CW         = $clog2(PERIOD_CYC + 1);

    reg [CW-1:0] cnt = 0;
    reg [CW-1:0] width = MIN_CYC;

    always @(posedge clk) begin
        if (rst) begin
            cnt   <= 0;
            pwm   <= 1'b0;
            width <= MIN_CYC;
        end else begin
            if (cnt == PERIOD_CYC - 1) begin
                cnt   <= 0;
                width <= MIN_CYC + ((position * RANGE_CYC) >> 8);   // latched once per period
            end else begin
                cnt <= cnt + 1'b1;
            end
            pwm <= (cnt < width);
        end
    end
endmodule
