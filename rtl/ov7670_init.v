`timescale 1ns / 1ps
//------------------------------------------------------------------------
// ov7670_init.v
//
// After power-up the OV7670 camera uses factory defaults (VGA, YUV). This
// module sends it a list of register writes over SCCB (the camera's I2C
// look-alike bus) using the existing i2c_master, so it outputs what the
// rest of the design expects: QVGA (320x240), RGB565.
//
// The list itself lives in ov7670_rom.v (generated from the open-source
// Linux OV7670 driver's tables, see that file). This module just steps
// through it, one write at a time.
//
// SCCB vs I2C: for WRITES the wire protocol is the same three bytes
//   [device address + write bit] [register] [value]
// The OV7670 write address is 0x42, i.e. 7-bit address 0x21. SCCB's 9th
// bit is "don't care" instead of a real ACK, so i2c_master's ack_error
// output is not meaningful here and is ignored.
//
// A ROM address of 8'hFF is not a write - it means "wait" (DELAY_CYCLES
// clocks). The camera needs time after power-up and after a soft reset.
//
// TEST_BARS=1 adds one last write that turns on the camera's built-in
// 8-bar color test pattern, which proves the camera -> FPGA -> HDMI path
// without depending on the lens or lighting.
//------------------------------------------------------------------------
module ov7670_init #(
    parameter integer DELAY_CYCLES = 1_250_000,  // 10 ms at 125 MHz
    parameter         TEST_BARS    = 0
) (
    input  wire clk,
    input  wire rst,
    input  wire go,          // pulse once to begin
    output reg  init_done,

    // Connects directly to an i2c_master instance
    output reg        i2c_start,
    output wire [6:0] i2c_dev_addr,
    output reg  [7:0] i2c_reg_addr,
    output reg  [7:0] i2c_reg_data,
    input  wire       i2c_busy,
    input  wire       i2c_done
);

    assign i2c_dev_addr = 7'h21;   // OV7670: 0x42 write / 0x43 read

    reg  [8:0] idx = 0;
    wire [7:0] rom_addr, rom_data;
    wire [8:0] last;
    ov7670_rom #(.TEST_BARS(TEST_BARS)) u_rom (
        .idx(idx), .addr(rom_addr), .data(rom_data), .last(last)
    );

    localparam S_IDLE = 0, S_ISSUE = 1, S_WAIT_BUSY = 2, S_WAIT_DONE = 3,
               S_NEXT = 4, S_DONE = 5, S_DELAY = 6;
    reg [2:0]  state = S_IDLE;
    reg [31:0] dcnt  = 0;

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            init_done <= 1'b0;
            i2c_start <= 1'b0;
            idx       <= 0;
        end else begin
            i2c_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    init_done <= 1'b0;
                    if (go) begin
                        idx   <= 0;
                        state <= S_ISSUE;
                    end
                end

                S_ISSUE: begin
                    if (rom_addr == 8'hFF) begin
                        dcnt  <= 0;
                        state <= S_DELAY;
                    end else begin
                        i2c_reg_addr <= rom_addr;
                        i2c_reg_data <= rom_data;
                        i2c_start    <= 1'b1;
                        state        <= S_WAIT_BUSY;
                    end
                end

                S_DELAY: begin
                    if (dcnt == DELAY_CYCLES - 1) state <= S_NEXT;
                    else                          dcnt  <= dcnt + 1'b1;
                end

                S_WAIT_BUSY: if (i2c_busy) state <= S_WAIT_DONE;

                S_WAIT_DONE: if (i2c_done) state <= S_NEXT;

                S_NEXT: begin
                    if (idx == last) begin
                        state <= S_DONE;
                    end else begin
                        idx   <= idx + 1'b1;
                        state <= S_ISSUE;
                    end
                end

                S_DONE: init_done <= 1'b1;   // stays until reset

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
