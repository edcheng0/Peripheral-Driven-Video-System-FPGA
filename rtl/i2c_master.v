`timescale 1ns / 1ps
//------------------------------------------------------------------------
// i2c_master.v
//
// A simple I2C master that can perform one operation: write a single
// byte to a specific register address on a specific I2C device. This
// is exactly what's needed to configure chips like the ADV7511 at
// startup (they expose their settings as a bank of 8-bit registers,
// each written the same way: device address, then register address,
// then the value).
//
// NOTE ON SCOPE: this is a "push" master only - no clock stretching
// support, no multi-master arbitration, no read support. That's fine
// for our use case (one master, one slave, startup configuration
// only), but this is not a general-purpose I2C peripheral.
//
// HOW TO USE: hold your device/register/data inputs stable, pulse
// "start" for one clock, then wait for "done" to pulse. Check
// "ack_error" at that point - if high, the chip didn't acknowledge
// (wrong address, chip not powered, wiring issue, etc).
//------------------------------------------------------------------------
module i2c_master #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer I2C_FREQ_HZ = 100_000,  // standard-mode I2C
    parameter integer EXT_SDA     = 0         // 1 = use sda_in_ext / sda_drive_low_o with an external I/O buffer
) (
    input  wire       clk,
    input  wire        rst,
    input  wire        start,
    input  wire [6:0]  dev_addr,   // 7-bit I2C device address
    input  wire [7:0]  reg_addr,
    input  wire [7:0]  reg_data,
    output reg         busy,
    output reg         done,       // pulses high for 1 clock when finished
    output reg         ack_error,

    output reg         scl,
    inout  wire        sda,
    input  wire        sda_in_ext,        // SDA level from an external buffer (EXT_SDA = 1)
    output wire        sda_drive_low_o    // 1 = SDA should be pulled low (EXT_SDA = 1)
);
    wire sda_sample;

    // ---- FSM state names and register ----
    // Declared before the phase counter below, which reads "state"
    // (strict tools such as xsim reject use-before-declaration).
    localparam S_IDLE       = 0,
               S_START      = 1,
               S_ADDR       = 2,   // sending device address + write bit
               S_ADDR_ACK   = 3,
               S_REG        = 4,   // sending register address byte
               S_REG_ACK    = 5,
               S_DATA       = 6,   // sending data byte
               S_DATA_ACK   = 7,
               S_STOP       = 8;

    reg [3:0] state = S_IDLE;

    // Each SCL period is divided into 4 quarter-phases:
    //   phase 0: SCL low,  change SDA here
    //   phase 1: SCL low,  let SDA settle
    //   phase 2: SCL high, SDA must be stable (this is where the
    //            receiving chip actually samples the bit)
    //   phase 3: SCL high, still stable
    localparam integer QUARTER_PERIOD = CLK_FREQ_HZ / (I2C_FREQ_HZ * 4);
    localparam integer QCNT_W = $clog2(QUARTER_PERIOD);

    reg [QCNT_W-1:0] q_count = 0;
    reg [1:0]        phase   = 0;
    reg              tick;   // pulses once per quarter-phase

    always @(posedge clk) begin
        if (rst || state == S_IDLE) begin
            // Hold the phase counter at 0 while idle so that whenever a
            // new transaction starts, it always begins phase-aligned -
            // otherwise "start" could land mid-cycle and desync the
            // whole bit sequence.
            q_count <= 0;
            phase   <= 0;
            tick    <= 0;
        end else if (q_count == QUARTER_PERIOD - 1) begin
            q_count <= 0;
            phase   <= phase + 1'b1;
            tick    <= 1'b1;
        end else begin
            q_count <= q_count + 1'b1;
            tick    <= 1'b0;
        end
    end

    // ---- SDA tri-state control ----
    reg sda_drive_low; // 1 = actively pull SDA low; 0 = release (pulled high externally)
    assign sda = sda_drive_low ? 1'b0 : 1'bz;
    assign sda_drive_low_o = sda_drive_low;
    assign sda_sample = (EXT_SDA != 0) ? sda_in_ext : sda;

    // ---- Main FSM (state/S_IDLE are declared near the top of the module) ----
    reg [7:0] shift_byte;
    reg [2:0] bit_index;   // counts 7 downto 0 while shifting a byte

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            ack_error     <= 1'b0;
            scl           <= 1'b1;
            sda_drive_low <= 1'b0;
        end else begin
            done <= 1'b0; // default; only pulses explicitly below

            case (state)
                S_IDLE: begin
                    scl <= 1'b1;
                    sda_drive_low <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        state <= S_START;
                    end
                end

                // START condition: SDA falls while SCL is high
                S_START: begin
                    if (tick) begin
                        case (phase)
                            0: sda_drive_low <= 1'b0; // SDA high, SCL still high from idle
                            1: sda_drive_low <= 1'b1; // SDA falls -> START condition
                            2: scl <= 1'b0;            // now bring SCL low to begin clocking
                            3: begin
                                shift_byte <= {dev_addr, 1'b0}; // address + write(0) bit
                                bit_index  <= 7;
                                state      <= S_ADDR;
                            end
                        endcase
                    end
                end

                S_ADDR: begin
                    if (tick) begin
                        case (phase)
                            0: sda_drive_low <= ~shift_byte[bit_index];
                            2: scl <= 1'b1;
                            3: begin
                                scl <= 1'b0;
                                if (bit_index == 0) begin
                                    state <= S_ADDR_ACK;
                                end else begin
                                    bit_index <= bit_index - 1'b1;
                                end
                            end
                        endcase
                    end
                end

                S_ADDR_ACK: begin
                    if (tick) begin
                        case (phase)
                            0: sda_drive_low <= 1'b0; // release SDA so slave can ACK
                            2: scl <= 1'b1;            // 9th clock pulse: SCL high for the ACK bit
                            3: begin
                                ack_error <= sda_sample;       // sample: slave pulls low = ACK (0)
                                scl <= 1'b0;
                                shift_byte <= reg_addr;
                                bit_index  <= 7;
                                state <= S_REG;
                            end
                        endcase
                    end
                end

                S_REG: begin
                    if (tick) begin
                        case (phase)
                            0: sda_drive_low <= ~shift_byte[bit_index];
                            2: scl <= 1'b1;
                            3: begin
                                scl <= 1'b0;
                                if (bit_index == 0)
                                    state <= S_REG_ACK;
                                else
                                    bit_index <= bit_index - 1'b1;
                            end
                        endcase
                    end
                end

                S_REG_ACK: begin
                    if (tick) begin
                        case (phase)
                            0: sda_drive_low <= 1'b0;
                            2: scl <= 1'b1;            // 9th clock pulse for the ACK bit
                            3: begin
                                ack_error <= ack_error | sda_sample;
                                scl <= 1'b0;
                                shift_byte <= reg_data;
                                bit_index  <= 7;
                                state <= S_DATA;
                            end
                        endcase
                    end
                end

                S_DATA: begin
                    if (tick) begin
                        case (phase)
                            0: sda_drive_low <= ~shift_byte[bit_index];
                            2: scl <= 1'b1;
                            3: begin
                                scl <= 1'b0;
                                if (bit_index == 0)
                                    state <= S_DATA_ACK;
                                else
                                    bit_index <= bit_index - 1'b1;
                            end
                        endcase
                    end
                end

                S_DATA_ACK: begin
                    if (tick) begin
                        case (phase)
                            0: sda_drive_low <= 1'b0;
                            2: scl <= 1'b1;            // 9th clock pulse for the ACK bit
                            3: begin
                                ack_error <= ack_error | sda_sample;
                                scl <= 1'b0;
                                state <= S_STOP;
                            end
                        endcase
                    end
                end

                // STOP condition: SDA rises while SCL is high
                S_STOP: begin
                    if (tick) begin
                        case (phase)
                            0: sda_drive_low <= 1'b1; // ensure SDA low first
                            1: scl <= 1'b1;            // SCL high...
                            2: sda_drive_low <= 1'b0;  // ...then SDA released -> STOP
                            3: begin
                                busy  <= 1'b0;
                                done  <= 1'b1;
                                state <= S_IDLE;
                            end
                        endcase
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
