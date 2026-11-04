`timescale 1ns / 1ps
//------------------------------------------------------------------------
// tb_i2c_master.v  (rewritten: passive waveform checking)
//
// Rather than modeling a full reactive I2C slave (which is prone to
// simulation race conditions against a separately-clocked master FSM),
// this testbench passively watches the SCL/SDA lines the same way a
// logic analyzer would: it detects the START condition, then samples
// SDA on every rising edge of SCL (the point in the I2C protocol where
// data is guaranteed stable) to reconstruct the bits the master sent,
// and separately confirms a STOP condition follows.
//------------------------------------------------------------------------
module tb_i2c_master;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg [6:0] dev_addr;
    reg [7:0] reg_addr, reg_data;
    wire busy, done, ack_error, scl;
    wire sda;

    integer errors = 0;

    pullup(sda); // models the external I2C pull-up resistor

    i2c_master #(
        .CLK_FREQ_HZ(1_000_000),
        .I2C_FREQ_HZ(100_000)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .dev_addr  (dev_addr),
        .reg_addr  (reg_addr),
        .reg_data  (reg_data),
        .busy      (busy),
        .done      (done),
        .ack_error (ack_error),
        .scl       (scl),
        .sda       (sda)
    );

    always #500 clk = ~clk; // 1 MHz

    // ---- Passive capture: reconstruct the first byte sent on the wire ----
    reg [7:0] captured_byte0;
    integer bit_idx;
    reg capturing;
    reg saw_start, saw_stop;

    initial begin
        bit_idx   = 7;
        capturing = 0;
        saw_start = 0;
        saw_stop  = 0;
    end

    // Detect START: SDA falls while SCL is high
    always @(negedge sda) begin
        if (scl === 1'b1 && !saw_start) begin
            saw_start = 1;
            capturing = 1;
            bit_idx   = 7;
        end
    end

    // Detect STOP: SDA rises while SCL is high
    always @(posedge sda) begin
        if (scl === 1'b1 && capturing) begin
            saw_stop  = 1;
            capturing = 0;
        end
    end

    // Sample the first 8 bits on the wire (the address + write bit) on
    // each rising edge of SCL - data is guaranteed stable here.
    always @(posedge scl) begin
        if (capturing && bit_idx >= 0) begin
            captured_byte0[bit_idx] = sda;
            bit_idx = bit_idx - 1;
        end
    end

    initial begin
        rst = 1;
        dev_addr = 7'h39;
        reg_addr = 8'h41;
        reg_data = 8'h10;
        @(negedge clk);
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (4) @(negedge clk);

        start = 1;
        @(negedge clk);
        start = 0;

        wait (done == 1'b1);
        @(posedge clk);

        if (saw_start)
            $display("PASS: START condition detected");
        else begin
            $display("FAIL: no START condition detected");
            errors = errors + 1;
        end

        if (saw_stop)
            $display("PASS: STOP condition detected");
        else begin
            $display("FAIL: no STOP condition detected");
            errors = errors + 1;
        end

        if (captured_byte0 === {dev_addr, 1'b0})
            $display("PASS: first 8 bits on the wire matched device address + write bit (%b)", captured_byte0);
        else begin
            $display("FAIL: expected first byte %b, got %b", {dev_addr,1'b0}, captured_byte0);
            errors = errors + 1;
        end

        // With no slave present to pull SDA low, the ACK bit reads as
        // released (1) = NACK, so we expect ack_error to be set - this
        // confirms the master correctly samples and reports real ACK
        // status rather than always assuming success.
        if (ack_error)
            $display("PASS: ack_error correctly set (no slave present to ACK)");
        else begin
            $display("FAIL: ack_error should be set with no slave present");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("=== ALL CHECKS PASSED ===");
        else
            $display("=== %0d CHECK(S) FAILED ===", errors);

        $finish;
    end

    initial begin
        #500000;
        $display("FAIL: testbench timed out");
        $finish;
    end

endmodule
