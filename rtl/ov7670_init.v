`timescale 1ns / 1ps
//------------------------------------------------------------------------
// ov7670_init.v
//
// After power-up the OV7670 camera uses factory defaults (VGA, YUV). This
// module sends it a list of register writes over SCCB (the camera's I2C
// look-alike bus) using the existing i2c_master, so it outputs what the
// rest of the design expects: QVGA (320x240), RGB565.
//
// SCCB vs I2C: for WRITES the wire protocol is the same three bytes
//   [device address + write bit] [register] [value]
// The OV7670 write address is 0x42, i.e. 7-bit address 0x21. SCCB's 9th
// bit is "don't care" instead of a real ACK, so i2c_master's ack_error
// output is not meaningful here and is ignored.
//
// ROM CONVENTION: a register address of 8'hFF is not a write - it means
// "wait" (DELAY_CYCLES clocks). The camera needs time after power-up and
// after a software reset before it listens.
//
// *** REGISTER VALUES ARE UNVERIFIED ***
// Written from memory of widely used open-source OV7670 configurations, NOT
// checked against the OV7670 datasheet / implementation guide (no camera
// in hand yet, and the datasheet is not in this repo). Treat every entry as
// "plausible, check on bring-up". Entries I am most/least sure of:
//   sure   : 0x12=0x80 soft reset; COM7 bit meanings (QVGA=bit4, RGB=bit2)
//   fairly : 0x40=0xD0 (COM15: RGB565, full 00-FF range), 0x3A, 0x8C, 0x11
//   least  : 0x3E/0x70/0x71/0x72/0x73 (QVGA down-scaling) and the color
//            bar bits (COM7 bit1 + COM17 0x42 bit3)
// If the picture is shifted, garbled or the wrong size, the windowing
// registers (HSTART/HSTOP/HREF/VSTRT/VSTOP/VREF = 0x17,0x18,0x32,0x19,
// 0x1A,0x03) are the next thing to add/tune.
//
// TEST_BARS=1 asks the camera for its built-in color bars, which proves the
// camera -> FPGA -> HDMI path without depending on the lens/exposure.
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

    localparam integer MAX_REGS = 16;
    localparam integer NUM_REGS = TEST_BARS ? 14 : 13;

    reg [7:0] rom_addr [0:MAX_REGS-1];
    reg [7:0] rom_data [0:MAX_REGS-1];

    initial begin
        rom_addr[0]  = 8'hFF; rom_data[0]  = 8'h00; // wait: camera power-up
        rom_addr[1]  = 8'h12; rom_data[1]  = 8'h80; // COM7: software reset
        rom_addr[2]  = 8'hFF; rom_data[2]  = 8'h00; // wait: reset
        rom_addr[3]  = 8'h12; rom_data[3]  = TEST_BARS ? 8'h16 : 8'h14; // COM7: QVGA + RGB (+color bar)
        rom_addr[4]  = 8'h40; rom_data[4]  = 8'hD0; // COM15: RGB565, output range 00-FF
        rom_addr[5]  = 8'h3A; rom_data[5]  = 8'h04; // TSLB
        rom_addr[6]  = 8'h8C; rom_data[6]  = 8'h00; // RGB444 off
        rom_addr[7]  = 8'h11; rom_data[7]  = 8'h01; // CLKRC: PCLK = XCLK / 2
        rom_addr[8]  = 8'h3E; rom_data[8]  = 8'h19; // COM14: DCW/scaling PCLK, /2
        rom_addr[9]  = 8'h72; rom_data[9]  = 8'h11; // SCALING_DCWCTR: /2 both directions
        rom_addr[10] = 8'h73; rom_data[10] = 8'hF1; // SCALING_PCLK_DIV
        rom_addr[11] = 8'h70; rom_data[11] = 8'h3A; // SCALING_XSC
        rom_addr[12] = 8'h71; rom_data[12] = 8'h35; // SCALING_YSC
        rom_addr[13] = 8'h42; rom_data[13] = 8'h08; // COM17: DSP color bar (only used if TEST_BARS)
        rom_addr[14] = 8'hFF; rom_data[14] = 8'h00;
        rom_addr[15] = 8'hFF; rom_data[15] = 8'h00;
    end

    localparam S_IDLE = 0, S_ISSUE = 1, S_WAIT_BUSY = 2, S_WAIT_DONE = 3,
               S_NEXT = 4, S_DONE = 5, S_DELAY = 6;
    reg [2:0]  state = S_IDLE;
    reg [4:0]  idx   = 0;
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
                    if (rom_addr[idx] == 8'hFF) begin
                        dcnt  <= 0;
                        state <= S_DELAY;
                    end else begin
                        i2c_reg_addr <= rom_addr[idx];
                        i2c_reg_data <= rom_data[idx];
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
                    if (idx == NUM_REGS - 1) begin
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
