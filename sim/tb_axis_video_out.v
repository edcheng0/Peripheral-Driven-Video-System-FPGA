`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tb_axis_video_out.v - checks that axis_video_out lines the DMA's pixel
// stream up with the display timing, and recovers from trouble.
//
// A stream source (acting like the video DMA reading a frame buffer over and
// over) sends a known 16x12 RGB565 image. It deliberately STARTS IN THE
// MIDDLE of a frame, so the DUT must find the start of a frame by itself.
// Every displayed pixel is compared with the expected value, frame by frame:
//   * after lock-on, several consecutive frames must be pixel-perfect
//   * then the source stalls for a few clocks in the middle of a frame:
//     that frame must come out damaged (proves the test can fail) and the
//     DUT must lock on again, with several perfect frames afterwards.
// ----------------------------------------------------------------------
module tb_axis_video_out;
    localparam W = 16, H = 12;
    integer errors = 0;

    reg clk = 0;
    always #16 clk = ~clk;

    function [15:0] img(input integer x, input integer y);
        reg [4:0] r; reg [5:0] g; reg [4:0] b;
        begin
            r = (x * 5 + y * 3 + 1) & 31;
            g = (x * 7 + y * 11 + 2) & 63;
            b = (x * 3 + y * 5 + 3) & 31;
            img = {r, g, b};
        end
    endfunction
    function [7:0] ex_r(input [15:0] p); ex_r = {p[15:11], p[15:13]}; endfunction
    function [7:0] ex_g(input [15:0] p); ex_g = {p[10:5],  p[10:9]};  endfunction
    function [7:0] ex_b(input [15:0] p); ex_b = {p[4:0],   p[4:2]};   endfunction

    // ---- display timing ----
    reg rst = 1;
    wire hs, vs, de;
    wire [9:0] px, py;
    video_timing_gen #(
        .CNT_W(10), .H_VISIBLE(W), .H_FRONT_PORCH(2), .H_SYNC_PULSE(2), .H_BACK_PORCH(2),
        .V_VISIBLE(H), .V_FRONT_PORCH(1), .V_SYNC_PULSE(1), .V_BACK_PORCH(1)
    ) tim (.clk_pixel(clk), .rst(rst), .hsync(hs), .vsync(vs), .data_enable(de),
           .pixel_x(px), .pixel_y(py));

    // ---- stream source (starts mid-frame at beat (5,3)) ----
    integer sx = 5, sy = 3;
    reg stall = 0;
    wire        tvalid = !stall;
    wire [15:0] tdata  = img(sx, sy);
    wire        tlast  = (sx == W - 1);
    wire        tuser  = (sx == 0) && (sy == 0);
    wire        tready;

    always @(posedge clk) begin
        if (tvalid && tready) begin
            if (sx == W - 1) begin
                sx <= 0;
                sy <= (sy == H - 1) ? 0 : sy + 1;
            end else sx <= sx + 1;
        end
    end

    // ---- DUT ----
    wire ho, vo, deo, locked_s;
    wire [7:0] r, g, b;
    axis_video_out #(.H_VIS(W), .V_VIS(H), .CNT_W(10)) dut (
        .clk_pixel(clk), .rst(rst),
        .hsync_in(hs), .vsync_in(vs), .de_in(de), .pixel_x(px), .pixel_y(py),
        .s_axis_tdata(tdata), .s_axis_tvalid(tvalid), .s_axis_tready(tready),
        .s_axis_tlast(tlast), .s_axis_tuser(tuser),
        .hsync_out(ho), .vsync_out(vo), .de_out(deo), .red(r), .green(g), .blue(b),
        .locked_to_stream(locked_s)
    );

    // coordinates of the pixel currently on the outputs (one clock behind the timing)
    reg [9:0] ox = 0, oy = 0;
    always @(posedge clk) begin ox <= px; oy <= py; end

    // sync/enable must be exactly the timing delayed by one clock
    reg hs_d, vs_d, de_d;
    always @(posedge clk) begin
        hs_d <= hs; vs_d <= vs; de_d <= de;
        if (!rst && ({ho, vo, deo} !== {hs_d, vs_d, de_d})) begin
            errors = errors + 1;
            if (errors < 5) $display("FAIL: sync/de not aligned at %0t", $time);
        end
    end

    // ---- per-frame checking ----
    localparam NF = 24;
    integer nf = 0, mism = 0;
    reg frame_ok [0:NF-1];
    integer inject_frame = 9;
    reg injected = 0;
    integer i;

    always @(posedge clk) if (!rst && deo) begin
        if (r !== ex_r(img(ox, oy)) || g !== ex_g(img(ox, oy)) || b !== ex_b(img(ox, oy)))
            mism = mism + 1;
        if (ox == W - 1 && oy == H - 1) begin       // last pixel of the frame
            if (nf < NF) frame_ok[nf] = (mism == 0);
            nf = nf + 1;
            mism = 0;
        end
    end

    // inject a stall in the middle of a visible frame
    always @(posedge clk) if (!rst && !injected && nf == inject_frame && de && px == 4 && py == 5) begin
        injected <= 1;
        stall    <= 1;
        repeat (5) @(posedge clk);
        stall    <= 0;
    end

    integer ok_before, ok_after, bad_mid, run_end;
    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        wait (nf >= NF);
        // frames 1..inject_frame-1 should be clean once locked (frame 0 may be blank)
        ok_before = 0;
        for (i = 2; i < inject_frame; i = i + 1) if (frame_ok[i]) ok_before = ok_before + 1;
        // the disturbed frame(s) right after the injection
        bad_mid = 0;
        for (i = inject_frame; i <= inject_frame + 1; i = i + 1) if (!frame_ok[i]) bad_mid = bad_mid + 1;
        // the final frames must all be clean again
        ok_after = 0;
        for (i = NF - 5; i < NF; i = i + 1) if (frame_ok[i]) ok_after = ok_after + 1;
        $display("frames clean before stall: %0d of %0d; damaged by stall: %0d; clean at the end: %0d of 5",
                 ok_before, inject_frame - 2, bad_mid, ok_after);
        if (ok_before != inject_frame - 2) begin errors = errors + 1; $display("FAIL: not locked/clean before the stall"); end
        if (bad_mid == 0)                  begin errors = errors + 1; $display("FAIL: stall did not disturb any frame (test has no teeth)"); end
        if (ok_after != 5)                 begin errors = errors + 1; $display("FAIL: did not recover after the stall"); end
        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else             $display("=== %0d CHECK(S) FAILED ===", errors);
        $finish;
    end

    initial begin #50_000_000; $display("FAIL: testbench timed out"); $finish; end
endmodule
