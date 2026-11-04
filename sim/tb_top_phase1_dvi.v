`timescale 1ns / 1ps
// ----------------------------------------------------------------------
// tb_top_phase1_dvi.v - Vivado xsim, whole-design check (needs unisim).
// Build with -d MODE_SVGA or -d MODE_720P to test the other tops.
// Acts like a very simple DVI receiver:
//   1. records all four lanes on every edge of the serial clock
//   2. finds word boundaries from the clock lane (it sends 0000011111)
//   3. decodes each data lane's 10-bit words back to 8-bit values using an
//      independent reference TMDS decoder
//   4. checks that a visible line (H_VIS pixels) comes out as the 8 color bars
//      (white, yellow, cyan, green, magenta, red, blue, black)
//   5. checks blanking uses control codes, and hsync shows up on the blue
//      lane as its control code
// ----------------------------------------------------------------------
`ifdef MODE_SVGA
  `define DUT_MOD   top_dvi_svga
  `define CORE      dut.core
  `define H_VIS     800
  `define H_TOT     1056
  `define H_SYNC_W  128
  `define BAR_W     100
  `define SAMP      1.0
  `define CODE_ACT  10'b0010101011
  `define CODE_IDLE 10'b1101010100
`elsif MODE_720P
  `define DUT_MOD   top_dvi_720p
  `define CORE      dut.core
  `define H_VIS     1280
  `define H_TOT     1650
  `define H_SYNC_W  40
  `define BAR_W     160
  `define SAMP      0.5
  `define CODE_ACT  10'b0010101011
  `define CODE_IDLE 10'b1101010100
`else
  `define DUT_MOD   top_phase1_dvi
  `define CORE      dut
  `define H_VIS     640
  `define H_TOT     800
  `define H_SYNC_W  96
  `define BAR_W     80
  `define SAMP      2.0
  `define CODE_ACT  10'b0101010100
  `define CODE_IDLE 10'b1010101011
`endif
module tb_top_phase1_dvi;
    reg sysclk = 0;
    wire tmds_clk_p, tmds_clk_n;
    wire [2:0] tmds_d_p, tmds_d_n;
    integer errors = 0;

    always #4 sysclk = ~sysclk;   // 125 MHz

    `DUT_MOD dut (.sysclk(sysclk),
                        .hdmi_tx_clk_p(tmds_clk_p), .hdmi_tx_clk_n(tmds_clk_n),
                        .hdmi_tx_p(tmds_d_p), .hdmi_tx_n(tmds_d_n));

    // ---- capture ----
    localparam NBITS = 40000;
    reg s_clk [0:NBITS-1];
    reg s_b   [0:NBITS-1];
    reg s_g   [0:NBITS-1];
    reg s_r   [0:NBITS-1];
    integer nb = 0;
    reg capturing = 0;
    always @(`CORE.clk_serial) begin
        #(`SAMP);
        if (capturing && nb < NBITS) begin
            s_clk[nb] = tmds_clk_p;
            s_b[nb]   = tmds_d_p[0];
            s_g[nb]   = tmds_d_p[1];
            s_r[nb]   = tmds_d_p[2];
            nb = nb + 1;
        end
        if (capturing && ((tmds_clk_p === tmds_clk_n) || (tmds_d_p === tmds_d_n))) begin
            errors = errors + 1;
            $display("FAIL: a pair has equal legs at %0t", $time);
        end
    end

    // ---- reference TMDS decoder (DVI 1.0 spec) ----
    function [7:0] tmds_decode(input [9:0] q);
        reg [7:0] d;
        integer i;
        begin
            d = q[9] ? ~q[7:0] : q[7:0];
            tmds_decode[0] = d[0];
            for (i = 1; i < 8; i = i + 1)
                tmds_decode[i] = q[8] ? (d[i] ^ d[i-1]) : (d[i] ~^ d[i-1]);
        end
    endfunction

    function is_control(input [9:0] q);
        is_control = (q == 10'b1101010100) || (q == 10'b0010101011) ||
                     (q == 10'b0101010100) || (q == 10'b1010101011);
    endfunction

    function [9:0] get_word(input integer lane, input integer start);
        integer b;
        begin
            for (b = 0; b < 10; b = b + 1)
                case (lane)
                    0: get_word[b] = s_b[start + b];
                    1: get_word[b] = s_g[start + b];
                    default: get_word[b] = s_r[start + b];
                endcase
        end
    endfunction

    function [7:0] bar_r(input integer bar);
        bar_r = (bar == 0 || bar == 1 || bar == 4 || bar == 5) ? 8'hFF : 8'h00;
    endfunction
    function [7:0] bar_g(input integer bar);
        bar_g = (bar <= 3) ? 8'hFF : 8'h00;
    endfunction
    function [7:0] bar_b(input integer bar);
        bar_b = (bar == 0 || bar == 2 || bar == 4 || bar == 6) ? 8'hFF : 8'h00;
    endfunction

    integer s, w, nw, first, i, bar;
    integer seen_hsync_code, seen_ctl_in_blank, seen_idle_code;
    reg [9:0] wb, wg, wr;

    initial begin
        wait (`CORE.locked === 1'b1);
        wait (`CORE.rst_pix === 1'b0);
        repeat (30) @(posedge `CORE.clk_pixel);
        capturing = 1;
        wait (nb >= NBITS);
        capturing = 0;

        // find word boundary: clock lane = 5 ones then 5 zeros (LSB first)
        s = -1;
        for (i = 0; i < 10 && s < 0; i = i + 1)
            if (s_clk[i]&s_clk[i+1]&s_clk[i+2]&s_clk[i+3]&s_clk[i+4] &
                ~(s_clk[i+5]|s_clk[i+6]|s_clk[i+7]|s_clk[i+8]|s_clk[i+9]))
                s = i;
        if (s < 0) begin
            $display("FAIL: clock lane pattern not found"); errors = errors + 1;
        end else begin
            // clock lane must repeat with period 10 bits everywhere
            for (i = s; i + 10 < NBITS; i = i + 1)
                if (s_clk[i] !== s_clk[i+10]) begin
                    errors = errors + 1;
                    if (errors < 5) $display("FAIL: clock lane not periodic at bit %0d", i);
                end
            nw = (NBITS - s) / 10;
            // find first control->data transition on the red lane
            first = -1;
            for (w = 1; w < nw && first < 0; w = w + 1)
                if (is_control(get_word(2, s + 10*(w-1))) && !is_control(get_word(2, s + 10*w)))
                    first = w;
            if (first < 0 || first + `H_VIS > nw) begin
                $display("FAIL: no complete visible line found in capture (first=%0d)", first);
                errors = errors + 1;
            end else begin
                $display("Visible line starts at captured word %0d", first);
                for (i = 0; i < `H_VIS; i = i + 1) begin
                    bar = i / `BAR_W;
                    wb = get_word(0, s + 10*(first+i));
                    wg = get_word(1, s + 10*(first+i));
                    wr = get_word(2, s + 10*(first+i));
                    if (tmds_decode(wb) !== bar_b(bar) || tmds_decode(wg) !== bar_g(bar) ||
                        tmds_decode(wr) !== bar_r(bar) ||
                        is_control(wb) || is_control(wg) || is_control(wr)) begin
                        errors = errors + 1;
                        if (errors < 8)
                            $display("FAIL: pixel %0d expected RGB=%h%h%h got %h%h%h", i, bar_r(bar),
                                     bar_g(bar), bar_b(bar), tmds_decode(wr), tmds_decode(wg), tmds_decode(wb));
                    end
                end
                // blanking after the line: 160 words, all control on all lanes,
                // and (active-low sync) the hsync-active code {v=1,h=0} = 0101010100 must
                // appear 96x on blue, with {v=1,h=1} = 1010101011 for the other 64
                seen_hsync_code = 0; seen_ctl_in_blank = 0; seen_idle_code = 0;
                for (i = `H_VIS; i < `H_TOT && (first + i) < nw; i = i + 1) begin
                    wb = get_word(0, s + 10*(first+i));
                    wg = get_word(1, s + 10*(first+i));
                    wr = get_word(2, s + 10*(first+i));
                    if (!is_control(wb) || !is_control(wg) || !is_control(wr)) begin
                        errors = errors + 1;
                        if (errors < 8) $display("FAIL: non-control word in blanking at pixel %0d", i);
                    end else seen_ctl_in_blank = seen_ctl_in_blank + 1;
                    if (wb == `CODE_ACT) seen_hsync_code = seen_hsync_code + 1;
                    if (wb == `CODE_IDLE) seen_idle_code = seen_idle_code + 1;
                end
                $display("Blanking words checked: %0d, hsync code words on blue: %0d (want %0d)",
                         seen_ctl_in_blank, seen_hsync_code, `H_SYNC_W);
                if (seen_hsync_code != `H_SYNC_W || seen_idle_code != (`H_TOT - `H_VIS - `H_SYNC_W)) begin
                    errors = errors + 1;
                    $display("FAIL: expected 96 hsync-active + 64 idle blue control words in the horizontal blanking");
                end
            end
        end
        if (errors == 0) $display("=== ALL CHECKS PASSED ===");
        else             $display("=== %0d CHECK(S) FAILED ===", errors);
        $finish;
    end
endmodule
