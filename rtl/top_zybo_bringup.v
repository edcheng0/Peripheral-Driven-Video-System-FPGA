`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// top_zybo_bringup.v - first thing to run on the Zybo Z7-20.
//
// Proves: the 125 MHz clock runs, JTAG programming works, and the pins for
// LEDs / buttons / switches are right (they are direct FPGA pins on this
// board, so you can finally SEE something).
//   LD0 : heartbeat, blinks once per second (proves the clock)
//   LD1 : BTN0, debounced
//   LD2 : BTN1, debounced
//   LD3 : SW0 (through a 2-flop synchronizer)
// BTN2 / BTN3 / SW1..3 are unused here; they are in the port list so the
// same three XDC files (leds, switches, buttons) work unchanged.
// ----------------------------------------------------------------------
module top_zybo_bringup (
    input  wire       sysclk,        // 125 MHz
    input  wire [3:0] btn,
    input  wire [3:0] sw,
    output wire [3:0] led
);
    localparam integer HALF_SEC = 62_500_000;     // 125 MHz / 2

    reg [25:0] cnt = 0;
    reg        beat = 1'b0;
    always @(posedge sysclk) begin
        if (cnt == HALF_SEC - 1) begin cnt <= 0; beat <= ~beat; end
        else cnt <= cnt + 1'b1;
    end

    wire b0, b1;
    debounce #(.DEBOUNCE_CYCLES(1_250_000)) db0 (.clk(sysclk), .rst(1'b0), .noisy_in(btn[0]), .clean_out(b0));
    debounce #(.DEBOUNCE_CYCLES(1_250_000)) db1 (.clk(sysclk), .rst(1'b0), .noisy_in(btn[1]), .clean_out(b1));

    (* ASYNC_REG = "TRUE" *) reg [1:0] sw0_s = 2'b00;
    always @(posedge sysclk) sw0_s <= {sw0_s[0], sw[0]};

    assign led = {sw0_s[1], b1, b0, beat};
endmodule
