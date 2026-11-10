`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// cam_ctrl.v - everything needed to set the OV7670 camera running, except
// receiving its pixels:
//   * gives the camera its input clock (xclk) from the pixel clock
//   * holds the camera in reset until the clocks are stable
//   * sends the register settings over the camera's I2C-like bus (SCCB)
//   * counts register writes the camera did not acknowledge (ack_errs)
//   * reinit (from the ARM): reset the camera and send the settings again
// Taken out of top_camera_dvi so the DDR3-frame-buffer design can reuse it.
// ----------------------------------------------------------------------
module cam_ctrl #(
    parameter TEST_BARS = 0,
    parameter QVGA      = 0       // this design uses full VGA (640x480)
) (
    input  wire sysclk,           // 125 MHz
    input  wire locked,           // MMCM lock (asynchronous to sysclk)
    input  wire clk_pixel,        // ~25.25 MHz, becomes the camera clock
    input  wire reinit,           // async level from the ARM: 1 = hold camera in reset
    input  wire arm_own,          // 1 = the ARM drives the camera bus itself (debug)
    input  wire arm_scl_low,      // ARM bit-bang: pull SCL low
    input  wire arm_sda_low,      // ARM bit-bang: pull SDA low
    output wire sda_in,           // SDA level, so the ARM can read the camera

    output wire cam_xclk,
    output wire cam_reset_n,
    output wire cam_pwdn,
    output wire cam_sioc,
    inout  wire cam_siod,
    output wire init_done,
    output reg  [7:0] ack_errs    // writes the camera did not acknowledge (saturates)
);

    clock_forward u_xclk (.clk(clk_pixel), .clk_out(cam_xclk));
    assign cam_pwdn = 1'b0;                 // 0 = normal operation

    (* ASYNC_REG = "TRUE" *) reg [1:0] lock_s = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] reinit_s = 2'b00;
    always @(posedge sysclk) begin
        lock_s   <= {lock_s[0], locked};
        reinit_s <= {reinit_s[0], reinit};
    end
    (* ASYNC_REG = "TRUE" *) reg [1:0] own_s = 2'b00;
    always @(posedge sysclk) own_s <= {own_s[0], arm_own};
    wire run = lock_s[1] & ~reinit_s[1];
    reg run_d = 1'b0;
    always @(posedge sysclk) run_d <= run;
    wire rst_sys = ~run | own_s[1];   // built-in init idles while the ARM owns the bus
    wire go      = run & ~run_d;            // one pulse when the camera is released

    assign cam_reset_n = run;               // hold the camera in reset until XCLK runs

    wire        i2c_start, i2c_busy, i2c_done, i2c_ack_error;
    wire [6:0]  i2c_dev;
    wire [7:0]  i2c_reg, i2c_val;
    ov7670_init #(.DELAY_CYCLES(1_250_000), .TEST_BARS(TEST_BARS), .QVGA(QVGA)) u_init (
        .clk(sysclk), .rst(rst_sys), .go(go), .init_done(init_done),
        .i2c_start(i2c_start), .i2c_dev_addr(i2c_dev), .i2c_reg_addr(i2c_reg),
        .i2c_reg_data(i2c_val), .i2c_busy(i2c_busy), .i2c_done(i2c_done)
    );
    wire scl_i2c;
    assign cam_sioc = arm_own ? ~arm_scl_low : scl_i2c;
    wire sda_i2c_low, sda_dummy, sda_rd;
    wire sda_low = sda_i2c_low | (arm_own & arm_sda_low);   // the camera bus master or the ARM pulls SDA low
    IOBUF u_sda_buf (.IO(cam_siod), .I(1'b0), .T(~sda_low), .O(sda_rd));
    assign sda_in = sda_rd;

    i2c_master #(.CLK_FREQ_HZ(125_000_000), .I2C_FREQ_HZ(100_000), .EXT_SDA(1)) u_sccb (
        .clk(sysclk), .rst(rst_sys), .start(i2c_start), .dev_addr(i2c_dev),
        .reg_addr(i2c_reg), .reg_data(i2c_val), .busy(i2c_busy), .done(i2c_done),
        .ack_error(i2c_ack_error), .scl(scl_i2c), .sda(sda_dummy),
        .sda_in_ext(sda_rd), .sda_drive_low_o(sda_i2c_low)
    );

    always @(posedge sysclk) begin
        if (rst_sys) ack_errs <= 8'd0;
        else if (i2c_done && i2c_ack_error && ack_errs != 8'hFF) ack_errs <= ack_errs + 1'b1;
    end
endmodule
