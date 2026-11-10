`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tb_cam_axis_bridge.v - checks the camera -> AXI4-Stream conversion.
// A behavioural OV7670 sends a known 32x24 RGB565 image (two bytes per
// pixel). For 3 frames the testbench checks every stream beat:
//   * exactly W*H beats per frame, in raster order, with the right pixel value
//   * tuser high on the first pixel of the frame and nowhere else
//   * tlast high on the last pixel of every line and nowhere else
// ----------------------------------------------------------------------
module tb_cam_axis_bridge;
    localparam W = 32, H = 24;
    integer errors = 0;

    reg pclk = 0;
    always #20 pclk = ~pclk;

    function [15:0] img(input integer x, input integer y);
        reg [4:0] r; reg [5:0] g; reg [4:0] b;
        begin
            r = (x * 7 + y * 3) & 31;
            g = ((x * x + y * 5) * 3) & 63;
            b = (x * 11 + y * y) & 31;
            img = {r, g, b};
        end
    endfunction

    // camera model
    reg       vsync = 1, href = 0;
    reg [7:0] d = 0;
    integer   frames_sent = 0, cx, cy;
    initial begin
        forever begin
            @(negedge pclk); vsync = 1; href = 0;
            repeat (3 * 80) @(negedge pclk);
            vsync = 0;
            repeat (80) @(negedge pclk);
            for (cy = 0; cy < H; cy = cy + 1) begin
                for (cx = 0; cx < W; cx = cx + 1) begin
                    href = 1; d = img(cx, cy) >> 8;    @(negedge pclk);
                    href = 1; d = img(cx, cy) & 8'hFF; @(negedge pclk);
                end
                href = 0; d = 8'hxx;
                repeat (30) @(negedge pclk);
            end
            repeat (20) @(negedge pclk);
            frames_sent = frames_sent + 1;
        end
    end

    wire [15:0] tdata;
    wire tvalid, tlast, tuser, ftog;
    cam_axis_bridge #(.WIDTH(W), .HEIGHT(H), .XW(6), .YW(5)) dut (
        .pclk(pclk), .vsync(vsync), .href(href), .d(d),
        .m_axis_tdata(tdata), .m_axis_tvalid(tvalid), .m_axis_tlast(tlast),
        .m_axis_tuser(tuser), .frame_toggle(ftog)
    );

    // monitor: count beats and check them against the expected raster position
    integer beat = 0, frame = 0, ex, ey, toggles = 0;
    reg ftog_d = 0;
    always @(posedge pclk) begin
        ftog_d <= ftog;
        if (ftog !== ftog_d && ftog_d !== 1'bx) toggles = toggles + 1;
        if (tvalid) begin
            ex = beat % W; ey = beat / W;
            if (tdata !== img(ex, ey)) begin
                errors = errors + 1;
                if (errors < 6) $display("FAIL: frame %0d beat %0d (%0d,%0d) data %h want %h", frame, beat, ex, ey, tdata, img(ex, ey));
            end
            if (tuser !== (beat == 0)) begin
                errors = errors + 1;
                if (errors < 6) $display("FAIL: tuser wrong at beat %0d", beat);
            end
            if (tlast !== (ex == W - 1)) begin
                errors = errors + 1;
                if (errors < 6) $display("FAIL: tlast wrong at beat %0d", beat);
            end
            beat = beat + 1;
            if (beat == W * H) begin beat = 0; frame = frame + 1; end
        end
    end

    initial begin
        wait (frames_sent >= 3);
        repeat (10) @(posedge pclk);
        $display("frames checked: %0d, leftover beats: %0d, frame toggles: %0d", frame, beat, toggles);
        if (frame < 3)  begin errors = errors + 1; $display("FAIL: fewer than 3 full frames seen"); end
        if (beat != 0)  begin errors = errors + 1; $display("FAIL: partial frame (beat count not a multiple of W*H)"); end
        if (toggles < 3) begin errors = errors + 1; $display("FAIL: frame_toggle did not flip once per frame"); end
        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else             $display("=== %0d CHECK(S) FAILED ===", errors);
        $finish;
    end
    initial begin #50_000_000; $display("FAIL: timed out"); $finish; end
endmodule
