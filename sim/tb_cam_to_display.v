`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tb_cam_to_display.v - end-to-end check of the camera -> display path.
//
// A behavioural OV7670 model sends a known 32x24 RGB565 test image (two
// bytes per pixel, VSYNC/HREF framing) on its own 25 MHz PCLK. The display
// side (a real video_timing_gen, 64x48 visible, unrelated 31 MHz clock)
// reads it back through the frame buffer, 2x upscaled. For each of the 4
// modes the testbench waits for a few camera frames, then compares EVERY
// displayed pixel against an independently computed expectation:
//   mode 0 raw      : RGB565 widened to 888
//   mode 1 gray     : BT.601 luma, shown as gray
//   mode 2 sobel    : |Gx|+|Gy| computed here straight from the formula
//                     (checked on the interior only: border isn't written)
//   mode 3 inverted : ~RGB565 widened to 888
// ----------------------------------------------------------------------
module tb_cam_to_display;
    localparam SW = 32, SH = 24;          // stored image size
    localparam DW = 64, DH = 48;          // displayed size (2x)

    integer errors = 0;

    // ---- clocks (deliberately unrelated) ----
    reg cam_pclk = 0, clk_pixel = 0;
    always #20  cam_pclk = ~cam_pclk;     // 25 MHz
    always #16  clk_pixel = ~clk_pixel;   // 31.25 MHz

    // ---- test image: any function that varies in all channels ----
    function [15:0] img(input integer x, input integer y);
        reg [4:0] r; reg [5:0] g; reg [4:0] b;
        begin
            r = (x * 7 + y * 3) & 31;
            g = ((x * x + y * 5) * 3) & 63;
            b = (x * 11 + y * y) & 31;
            img = {r, g, b};
        end
    endfunction

    function [7:0] ex_r(input [15:0] p); ex_r = {p[15:11], p[15:13]}; endfunction
    function [7:0] ex_g(input [15:0] p); ex_g = {p[10:5],  p[10:9]};  endfunction
    function [7:0] ex_b(input [15:0] p); ex_b = {p[4:0],   p[4:2]};   endfunction
    function [7:0] luma(input [15:0] p);
        integer s;
        begin s = 77 * ex_r(p) + 150 * ex_g(p) + 29 * ex_b(p); luma = s >> 8; end
    endfunction
    function [15:0] g565(input [7:0] g); g565 = {g[7:3], g[7:2], g[7:3]}; endfunction

    function [7:0] sobel_at(input integer x, input integer y);
        integer gx, gy, a;
        begin
            gx = (luma(img(x+1,y-1)) + 2*luma(img(x+1,y)) + luma(img(x+1,y+1)))
               - (luma(img(x-1,y-1)) + 2*luma(img(x-1,y)) + luma(img(x-1,y+1)));
            gy = (luma(img(x-1,y+1)) + 2*luma(img(x,y+1)) + luma(img(x+1,y+1)))
               - (luma(img(x-1,y-1)) + 2*luma(img(x,y-1)) + luma(img(x+1,y-1)));
            if (gx < 0) gx = -gx;
            if (gy < 0) gy = -gy;
            a = gx + gy;
            sobel_at = (a > 255) ? 8'd255 : a;
        end
    endfunction

    // ---- camera model ----
    reg       cam_vsync = 1, cam_href = 0;
    reg [7:0] cam_d = 0;
    integer   cam_frames = 0;
    integer   cx, cy;
    initial begin
        forever begin
            // vertical blanking: VSYNC high for a few line-times
            @(negedge cam_pclk); cam_vsync = 1; cam_href = 0;
            repeat (3 * 150) @(negedge cam_pclk);
            cam_vsync = 0;
            repeat (150) @(negedge cam_pclk);
            for (cy = 0; cy < SH; cy = cy + 1) begin
                for (cx = 0; cx < SW; cx = cx + 1) begin
                    cam_href = 1; cam_d = img(cx, cy) >> 8;   @(negedge cam_pclk);
                    cam_href = 1; cam_d = img(cx, cy) & 8'hFF; @(negedge cam_pclk);
                end
                cam_href = 0; cam_d = 8'hxx;
                repeat (40) @(negedge cam_pclk);              // horizontal blanking
            end
            repeat (50) @(negedge cam_pclk);
            cam_frames = cam_frames + 1;
        end
    end

    // ---- display side ----
    reg rst = 1;
    wire hs, vs, de;
    wire [9:0] px, py;
    video_timing_gen #(
        .CNT_W(10), .H_VISIBLE(DW), .H_FRONT_PORCH(4), .H_SYNC_PULSE(4), .H_BACK_PORCH(4),
        .V_VISIBLE(DH), .V_FRONT_PORCH(2), .V_SYNC_PULSE(2), .V_BACK_PORCH(2)
    ) tim (.clk_pixel(clk_pixel), .rst(rst), .hsync(hs), .vsync(vs),
           .data_enable(de), .pixel_x(px), .pixel_y(py));

    reg [1:0] mode = 0;
    wire ho, vo, deo;
    wire [7:0] r, g, b;
    cam_to_display #(.SRC_W(SW), .SRC_H(SH), .XW(6), .YW(5), .SHIFT(1), .CNT_W(10)) dut (
        .cam_pclk(cam_pclk), .cam_vsync(cam_vsync), .cam_href(cam_href), .cam_d(cam_d),
        .mode(mode),
        .clk_pixel(clk_pixel), .hsync_in(hs), .vsync_in(vs), .de_in(de),
        .pixel_x(px), .pixel_y(py),
        .hsync_out(ho), .vsync_out(vo), .de_out(deo), .red(r), .green(g), .blue(b)
    );

    // coordinates of the pixel currently emerging (pixel_reader adds 1 clock)
    reg [9:0] ox, oy;
    always @(posedge clk_pixel) begin ox <= px; oy <= py; end

    // sync alignment check: de_out/hsync_out/vsync_out are exactly the inputs delayed 1 clock
    reg hs_d, vs_d, de_d;
    always @(posedge clk_pixel) begin
        hs_d <= hs; vs_d <= vs; de_d <= de;
        if (!rst && ({ho, vo, deo} !== {hs_d, vs_d, de_d})) begin
            errors = errors + 1;
            if (errors < 5) $display("FAIL: sync/de not aligned at %0t", $time);
        end
    end

    integer m, checked, mism;
    reg checking = 0;
    reg [15:0] exp565;
    integer sx, sy;
    always @(posedge clk_pixel) if (checking && deo) begin
        sx = ox >> 1; sy = oy >> 1;
        case (mode)
            0: exp565 = img(sx, sy);
            1: exp565 = g565(luma(img(sx, sy)));
            2: exp565 = g565(sobel_at(sx, sy));
            default: exp565 = ~img(sx, sy);
        endcase
        // sobel: only interior pixels are written
        if (mode != 2 || (sx >= 1 && sx <= SW-2 && sy >= 1 && sy <= SH-2)) begin
            checked = checked + 1;
            if (r !== ex_r(exp565) || g !== ex_g(exp565) || b !== ex_b(exp565)) begin
                mism = mism + 1;
                if (mism < 6)
                    $display("FAIL mode %0d src(%0d,%0d): got %h%h%h want %h%h%h", mode, sx, sy,
                             r, g, b, ex_r(exp565), ex_g(exp565), ex_b(exp565));
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk_pixel);
        rst = 0;
        for (m = 0; m < 4; m = m + 1) begin
            mode = m;
            checked = 0; mism = 0; checking = 0;
            // let at least 3 whole camera frames pass after the mode change
            begin : wait_frames
                integer f0;
                f0 = cam_frames;
                wait (cam_frames >= f0 + 3);
            end
            checking = 1;
            // check one whole display frame (+ margin)
            repeat (2) begin
                @(posedge vs); @(negedge vs);
            end
            @(posedge vs);
            checking = 0;
            $display("mode %0d: %0d pixels checked, %0d mismatches", m, checked, mism);
            if (checked < DW * DH / 2) begin
                errors = errors + 1; $display("FAIL: too few pixels checked in mode %0d", m);
            end
            errors = errors + mism;
        end
        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else             $display("=== %0d CHECK(S) FAILED ===", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL: testbench timed out");
        $finish;
    end
endmodule
