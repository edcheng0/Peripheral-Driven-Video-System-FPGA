`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tb_display_filter.v - checks the four display modes of display_filter.
// A known 16x12 image is sent through a small display timing; for each mode
// every visible pixel of the later frames is compared with a value computed
// independently here (gray formula, invert, Sobel from its definition), and
// sync/data-enable must come out exactly DELAY+1 clocks after they went in.
// ----------------------------------------------------------------------
module tb_display_filter;
    localparam W = 16, H = 12, HT = 22, VT = 15;
    localparam DELAY = HT + 2;
    localparam FRAME = HT * VT;
    integer errors = 0, checked = 0;

    reg clk = 0;
    always #16 clk = ~clk;

    function [7:0] cr(input integer x, input integer y); cr = (x * 37 + y * 11 + 5) & 255; endfunction
    function [7:0] cg(input integer x, input integer y); cg = (x * 13 + y * 71 + 9) & 255; endfunction
    function [7:0] cb(input integer x, input integer y); cb = (x * 91 + y * 29 + 1) & 255; endfunction
    function integer gry(input integer x, input integer y);
        integer s;
        begin s = 77 * cr(x, y) + 150 * cg(x, y) + 29 * cb(x, y); gry = s >> 8; end
    endfunction
    function integer sob(input integer x, input integer y);
        integer gx, gy, m;
        begin
            gx = gry(x+1,y-1) + 2*gry(x+1,y) + gry(x+1,y+1) - gry(x-1,y-1) - 2*gry(x-1,y) - gry(x-1,y+1);
            gy = gry(x-1,y+1) + 2*gry(x,y+1) + gry(x+1,y+1) - gry(x-1,y-1) - 2*gry(x,y-1) - gry(x+1,y-1);
            if (gx < 0) gx = -gx;
            if (gy < 0) gy = -gy;
            m = gx + gy;
            sob = (m > 255) ? 255 : m;
        end
    endfunction

    reg rst = 1;
    reg [1:0] mode = 0;
    wire hs, vs, de;
    wire [9:0] px, py;
    video_timing_gen #(
        .CNT_W(10), .H_VISIBLE(W), .H_FRONT_PORCH(2), .H_SYNC_PULSE(2), .H_BACK_PORCH(2),
        .V_VISIBLE(H), .V_FRONT_PORCH(1), .V_SYNC_PULSE(1), .V_BACK_PORCH(1)
    ) tim (.clk_pixel(clk), .rst(rst), .hsync(hs), .vsync(vs), .data_enable(de),
           .pixel_x(px), .pixel_y(py));

    wire [7:0] r = de ? cr(px, py) : 8'd0;
    wire [7:0] g = de ? cg(px, py) : 8'd0;
    wire [7:0] b = de ? cb(px, py) : 8'd0;

    wire ohs, ovs, ode;
    wire [7:0] orr, og, ob;
    display_filter #(.WIDTH(W), .XW(10), .YW(9), .DELAY(DELAY)) dut (
        .clk(clk), .mode(mode), .hs_in(hs), .vs_in(vs), .de_in(de),
        .r_in(r), .g_in(g), .b_in(b),
        .hs_out(ohs), .vs_out(ovs), .de_out(ode), .r_out(orr), .g_out(og), .b_out(ob));

    // history of what went in
    reg        h_hs [0:8191], h_vs [0:8191], h_de [0:8191];
    integer    h_x  [0:8191], h_y  [0:8191];
    integer cyc = 0, seg_start = 0;
    always @(posedge clk) begin
        h_hs[cyc] = hs; h_vs[cyc] = vs; h_de[cyc] = de; h_x[cyc] = px; h_y[cyc] = py;
        cyc = cyc + 1;
    end

    // check on the falling edge, one cycle's outputs at a time
    integer hh, x, y, e, got_ok;
    reg [23:0] expc;
    always @(negedge clk) if (!rst && cyc > DELAY + 2) begin
        hh = cyc - 1 - (DELAY + 1);
        if (hh >= 0 && cyc > seg_start + 2 * FRAME + 40) begin
            if (ohs !== h_hs[hh] || ovs !== h_vs[hh] || ode !== h_de[hh]) begin
                errors = errors + 1;
                if (errors < 10) $display("SYNC mismatch at cyc %0d", cyc);
            end
            if (h_de[hh]) begin
                x = h_x[hh]; y = h_y[hh];
                case (mode)
                    2'd0: expc = {cr(x,y), cg(x,y), cb(x,y)};
                    2'd1: expc = {gry(x,y)[7:0], gry(x,y)[7:0], gry(x,y)[7:0]};
                    2'd2: begin
                        if (x >= 1 && x <= W-2 && y >= 1 && y <= H-2) e = sob(x, y); else e = 0;
                        expc = {e[7:0], e[7:0], e[7:0]};
                    end
                    default: expc = ~{cr(x,y), cg(x,y), cb(x,y)};
                endcase
                checked = checked + 1;
                if ({orr, og, ob} !== expc) begin
                    errors = errors + 1;
                    if (errors < 10) $display("PIXEL mismatch mode %0d (%0d,%0d): got %h want %h", mode, x, y, {orr,og,ob}, expc);
                end
            end
        end
    end

    integer m;
    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        for (m = 0; m < 4; m = m + 1) begin
            mode = m; seg_start = cyc;
            repeat (5 * FRAME) @(posedge clk);
        end
        $display("checked %0d visible pixels, %0d errors", checked, errors);
        if (checked < 4 * 3 * W * H - 100) begin errors = errors + 1; $display("too few pixels checked"); end
        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else $display("=== %0d ERRORS ===", errors);
        $finish;
    end
endmodule
