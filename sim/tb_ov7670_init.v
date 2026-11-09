`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tb_ov7670_init.v - runs ov7670_init + i2c_master against a small SCCB
// slave model that really decodes the bus (START, 3 bytes, STOP) and checks:
//   * every transaction is [0x42][reg][value] and matches the ROM, in order
//   * the "wait" (0xFF) entries are not sent as writes, and the pause after
//     the soft-reset write is at least DELAY_CYCLES long
//   * init_done only rises after the last write
// Runs twice (TEST_BARS = 0 and 1) to check the ROM length switch.
// ----------------------------------------------------------------------
module tb_ov7670_init;
    integer errors = 0;
    wire [1:0] done_both;

    sccb_case #(.TEST_BARS(0)) c0 (.done(done_both[0]), .errs());
    sccb_case #(.TEST_BARS(1)) c1 (.done(done_both[1]), .errs());

    initial begin
        wait (done_both == 2'b11);
        #1000;
        errors = c0.errors + c1.errors;
        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else             $display("=== %0d CHECK(S) FAILED ===", errors);
        $finish;
    end
    initial begin #1_000_000_000; $display("FAIL: testbench timed out"); $finish; end
endmodule

module sccb_case #(parameter TEST_BARS = 0) (
    output reg done,
    output wire [31:0] errs
);
    localparam DLY = 40;
    reg clk = 0, rst = 1, go = 0;
    always #500 clk = ~clk;       // 1 MHz sim clock
    integer errors = 0;
    assign errs = errors;
    initial done = 0;

    wire init_done, i2c_start, i2c_busy, i2c_done, scl, ack_error;
    wire [6:0] dev; wire [7:0] ra, rd;
    wire sda;
    pullup(sda);

    ov7670_init #(.DELAY_CYCLES(DLY), .TEST_BARS(TEST_BARS)) dut (
        .clk(clk), .rst(rst), .go(go), .init_done(init_done),
        .i2c_start(i2c_start), .i2c_dev_addr(dev), .i2c_reg_addr(ra), .i2c_reg_data(rd),
        .i2c_busy(i2c_busy), .i2c_done(i2c_done));
    i2c_master #(.CLK_FREQ_HZ(1_000_000), .I2C_FREQ_HZ(200_000)) i2c (
        .clk(clk), .rst(rst), .start(i2c_start), .dev_addr(dev), .reg_addr(ra), .reg_data(rd),
        .busy(i2c_busy), .done(i2c_done), .ack_error(ack_error), .scl(scl), .sda(sda));

    // ---- SCCB slave model ----
    reg       pull = 0;
    assign sda = pull ? 1'b0 : 1'bz;
    reg       active = 0;
    integer   bitcnt = 0, byte_idx = 0;
    reg [7:0] shreg = 0;
    reg [7:0] bytes [0:2];
    integer   n_writes = 0;
    // our own copy of the ROM, read through chk_idx, to know what SHOULD be sent
    reg  [8:0] chk_idx = 0;
    wire [7:0] ca, cd;
    wire [8:0] clast;
    ov7670_rom #(.TEST_BARS(TEST_BARS)) chk (.idx(chk_idx), .addr(ca), .data(cd), .last(clast));
    integer   exp_writes = 0, ii;
    real      t_last_stop = 0, t_start = 0;
    reg       prev_was_reset = 0;

    always @(negedge sda) if (scl === 1'b1) begin
        active = 1; bitcnt = 0; byte_idx = 0; pull = 0;
        t_start = $realtime;
    end
    always @(posedge sda) if (scl === 1'b1 && active) begin
        active = 0;
        if (byte_idx != 3) begin
            errors = errors + 1; $display("FAIL: transaction had %0d bytes, want 3", byte_idx);
        end else begin
            // skip ROM wait entries to find which write this should be
            while (ca == 8'hFF) begin chk_idx = chk_idx + 1; #1; end
            if (bytes[0] !== 8'h42 || bytes[1] !== ca || bytes[2] !== cd) begin
                errors = errors + 1;
                if (errors < 8)
                    $display("FAIL: write %0d got %h %h %h, ROM says 42 %h %h", n_writes,
                             bytes[0], bytes[1], bytes[2], ca, cd);
            end
            chk_idx = chk_idx + 1; #1;
            n_writes = n_writes + 1;
        end
        t_last_stop = $realtime;
    end
    always @(posedge scl) if (active) begin
        if (bitcnt < 8) begin shreg = {shreg[6:0], sda}; bitcnt = bitcnt + 1; end
        else begin bytes[byte_idx] = shreg; byte_idx = byte_idx + 1; bitcnt = 0; end
    end
    always @(negedge scl) if (active) pull <= (bitcnt == 8);

    // gap check: START of write #2 (index 1 after reset write) must be >= DLY clocks after the reset write's STOP
    always @(negedge sda) if (scl === 1'b1 && n_writes == 1) begin
        if (($realtime - t_last_stop) < DLY * 1000.0) begin
            errors = errors + 1;
            $display("FAIL: pause after soft reset was %0f ns, want >= %0d", $realtime - t_last_stop, DLY * 1000);
        end
    end

    initial begin
        // how many real writes (not waits) does the ROM contain?
        for (ii = 0; ii <= 9'd511; ii = ii + 1) begin
            chk_idx = ii; #1;
            if (ii <= clast && ca != 8'hFF) exp_writes = exp_writes + 1;
        end
        chk_idx = 0; #1;
        repeat (4) @(negedge clk);
        rst = 0;
        repeat (4) @(negedge clk);
        go = 1; @(negedge clk); go = 0;
        wait (init_done == 1'b1);
        repeat (4) @(posedge clk);
        if (n_writes !== exp_writes) begin
            errors = errors + 1;
            $display("FAIL: TEST_BARS=%0d expected %0d writes, saw %0d", TEST_BARS, exp_writes, n_writes);
        end else
            $display("TEST_BARS=%0d: %0d register writes sent and matched the ROM", TEST_BARS, n_writes);
        done = 1;
    end
endmodule
