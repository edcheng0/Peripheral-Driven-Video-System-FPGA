# gen_ov7670_rom.awk - regenerates rtl/ov7670_rom.v from the Linux ov7670 driver tables.
# Get the source:  curl -L https://raw.githubusercontent.com/torvalds/linux/master/drivers/media/i2c/ov7670.c -o ov7670.c
# Run (file given twice on purpose):  gawk -f scripts/gen_ov7670_rom.awk ov7670.c ov7670.c > rtl/ov7670_rom.v

# gen_rom.awk - builds rtl/ov7670_rom.v from the Linux ov7670.c register tables.
# usage: gawk -f gen_rom.awk ov7670.c ov7670.c > ov7670_rom.v   (file given twice: pass 1 = macros, pass 2 = tables)

function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

function strip(line,   p, q) {
    # remove /* ... */ comments, including ones that span lines
    while (1) {
        if (incomment) {
            q = index(line, "*/")
            if (q == 0) return ""
            line = substr(line, q + 2); incomment = 0
        }
        p = index(line, "/*")
        if (p == 0) break
        q = index(substr(line, p + 2), "*/")
        if (q == 0) { line = substr(line, 1, p - 1); incomment = 1; break }
        line = substr(line, 1, p - 1) " " substr(line, p + 2 + q + 1)
    }
    sub(/\/\/.*/, "", line)
    return line
}

function ev(expr,   n, parts, i, t, v) {
    expr = trim(expr); gsub(/[()]/, "", expr)
    n = split(expr, parts, "|"); v = 0
    for (i = 1; i <= n; i++) {
        t = trim(parts[i])
        if (t ~ /^0[xX][0-9a-fA-F]+$/)      v = or(v, strtonum(t))
        else if (t ~ /^[0-9]+$/)            v = or(v, t + 0)
        else if (t in raw)                  v = or(v, ev(raw[t]))
        else { print "UNRESOLVED: " t > "/dev/stderr"; bad = 1 }
    }
    return v
}

# ---- pass 1: macros ----
NR == FNR {
    if ($1 == "#define" && NF >= 3) {
        line = strip($0); split(line, w, /[ \t]+/)
        name = w[2]; rest = line; sub(/^[ \t]*#define[ \t]+[A-Za-z0-9_]+[ \t]+/, "", rest)
        if (name !~ /\(/) raw[name] = trim(rest)
    }
    next
}

# ---- pass 2: tables ----
function add(a, d) { na++; A[na] = a; D[na] = d; ALT[na] = 0 }
# addq: value depends on the QVGA parameter (dq when QVGA=1, dv when QVGA=0)
function addq(a, dq, dv) { na++; A[na] = a; D[na] = dq; ALTV[na] = dv; ALT[na] = 1 }

function parse_table(first_skip_com7,   line, s, e, ent, c, ra, rv, ok) {
    line = strip($0)
    while (match(line, /\{[^{}]*\}/)) {
        ent = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
        c = index(ent, ",")
        if (c == 0) continue
        ra = ev(substr(ent, 1, c - 1)); rv = ev(substr(ent, c + 1))
        if (ra == 255 && rv == 255) { intable = 0; return }      # end marker
        T[++nt] = ra; V[nt] = rv
    }
}

/ov7670_default_regs\[\] = \{/ { intable = 1; table = "def"; nt = 0; incomment = 0; next }
/ov7670_fmt_rgb565\[\] = \{/   { intable = 1; table = "rgb"; nt = 0; incomment = 0; next }
intable { parse_table(); if (!intable) { for (i = 1; i <= nt; i++) { if (table == "def") { DA[i] = T[i]; DV[i] = V[i] } else { RA[i] = T[i]; RV[i] = V[i] } } if (table == "def") ndef = nt; else nrgb = nt } }

END {
    if (bad) exit 1
    # ---- assemble the sequence ----
    na = 0
    add(255, 0)                      # wait: power-up
    add(18, 128)                     # COM7: software reset
    add(255, 0)                      # wait: reset
    for (i = 1; i <= ndef; i++) {
        if (DA[i] == 18 && DV[i] == 128) continue       # skip the driver's own reset
        add(DA[i], DV[i])
    }
    addq(18, or(ev("COM7_RGB"), ev("COM7_FMT_QVGA")), ev("COM7_RGB"))    # COM7: RGB, +QVGA bit if QVGA
    for (i = 2; i <= nrgb; i++) add(RA[i], RV[i])       # RGB565 settings (first entry was COM7)
    add(21, 0)                                           # COM10: default sync polarity
    # window for QVGA: hstart 168 hstop 24 vstart 12 vstop 492 (driver values)
    addq(23, 168 / 8, 158 / 8); addq(24, 24 / 8, 14 / 8)  # HSTART, HSTOP  (QVGA / VGA driver values)
    addq(50, 128, 182)                                    # HREF  (QVGA 0x80 / VGA 0xB6)
    addq(25, 12 / 4, 10 / 4); addq(26, 492 / 4, 490 / 4)  # VSTART, VSTOP
    addq(3, 0, 10)                                        # VREF  (QVGA 0x00 / VGA 0x0A)
    add(17, 1)                                           # CLKRC: 1 = PCLK is XCLK/2 (rewritten last, per driver)
    nbase = na
    add(113, or(ev("0x35"), 128))                        # SCALING_YSC | test pattern bit = 8-bar color bar

    print "`timescale 1ns / 1ps"
    print "// ----------------------------------------------------------------------"
    print "// ov7670_rom.v - GENERATED FILE (do not edit by hand)."
    print "//"
    print "// OV7670 register sequence: soft reset, OmniVision default settings, then"
    print "// QVGA (320x240, QVGA=1) or VGA (640x480, QVGA=0) + RGB565 output. Register"
    print "// addresses/values are taken from the"
    print "// open-source Linux V4L2 OV7670 driver (drivers/media/i2c/ov7670.c), whose"
    print "// default table is documented there as obtained from OmniVision. Only the"
    print "// register numbers/values are used here; the sequence is assembled by a script."
    print "// Entry address 8'hFF means \"wait\" (not a register write)."
    print "// Last entry (TEST_BARS=1 only): SCALING_YSC bit 7 = 8-bar color test pattern."
    print "// Not checked against the OmniVision datasheet PDF (could not read it)."
    print "// ----------------------------------------------------------------------"
    print "module ov7670_rom #(parameter TEST_BARS = 0, parameter QVGA = 1) ("
    print "    input  wire [8:0] idx,"
    print "    output reg  [7:0] addr,"
    print "    output reg  [7:0] data,"
    print "    output wire [8:0] last     // index of the final entry to send"
    print ");"
    printf "    assign last = TEST_BARS ? 9'd%d : 9'd%d;\n", nbase, nbase - 1
    print "    always @(*) begin"
    print "        case (idx)"
    for (i = 1; i <= na; i++) {
        if (ALT[i])
            printf "            9'd%d: begin addr = 8'h%02X; data = QVGA ? 8'h%02X : 8'h%02X; end\n", i - 1, A[i], D[i], ALTV[i]
        else
            printf "            9'd%d: begin addr = 8'h%02X; data = 8'h%02X; end\n", i - 1, A[i], D[i]
    }
    print "            default: begin addr = 8'hFF; data = 8'h00; end"
    print "        endcase"
    print "    end"
    print "endmodule"
}
