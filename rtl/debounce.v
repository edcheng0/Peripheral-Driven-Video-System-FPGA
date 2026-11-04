`timescale 1ns / 1ps
//------------------------------------------------------------------------
// debounce.v
//
// Simple counter-based button debouncer.
// A button input is only accepted as "changed" after it has been
// stable for DEBOUNCE_CYCLES clock cycles in a row.
//
// At a 100 MHz clock, DEBOUNCE_CYCLES = 1_000_000 gives a 10 ms
// debounce window, which is plenty for a mechanical push button.
//------------------------------------------------------------------------
module debounce #(
    parameter integer DEBOUNCE_CYCLES = 1_000_000
) (
    input  wire clk,
    input  wire rst,
    input  wire noisy_in,   // raw button/switch input (already synchronized, see note below)
    output reg  clean_out   // debounced, glitch-free output
);

    // Width needed to count up to DEBOUNCE_CYCLES
    localparam integer CNT_W = $clog2(DEBOUNCE_CYCLES + 1);

    reg [CNT_W-1:0] count;
    reg sync0, sync1; // two-flop synchronizer for the async input

    // Always synchronize any off-chip signal into your clock domain
    // before you do anything else with it.
    always @(posedge clk) begin
        if (rst) begin
            sync0 <= 1'b0;
            sync1 <= 1'b0;
        end else begin
            sync0 <= noisy_in;
            sync1 <= sync0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            count     <= 0;
            clean_out <= 1'b0;
        end else if (sync1 == clean_out) begin
            // Input agrees with what we're currently outputting -> reset counter
            count <= 0;
        end else begin
            // Input disagrees with output -> count how long it's been different
            count <= count + 1'b1;
            if (count >= DEBOUNCE_CYCLES - 1) begin
                clean_out <= sync1;
                count     <= 0;
            end
        end
    end

endmodule
