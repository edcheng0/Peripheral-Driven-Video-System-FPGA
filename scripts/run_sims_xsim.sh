#!/usr/bin/env bash
# ----------------------------------------------------------------------
# run_sims_xsim.sh - run every testbench with Vivado's xsim (no Icarus).
# Usage (from anywhere, Git Bash):  bash scripts/run_sims_xsim.sh
# Needs Vivado's bin folder on PATH, or set VIVADO_BIN below / in the env.
# Includes the tests that need Xilinx primitives (MMCM, OSERDES), which
# Icarus can't run: those use the unisim + secureip libraries and glbl.v.
# Output goes to sim/build_xsim/ (git-ignored).
# ----------------------------------------------------------------------
set -u
cd "$(dirname "$0")/.."
VIVADO_BIN="${VIVADO_BIN:-/c/AMDDesignTools/2025.2/Vivado/bin}"
export PATH="$PATH:$VIVADO_BIN"
GLBL="$(cygpath -w "$VIVADO_BIN/../data/verilog/src/glbl.v" 2>/dev/null || echo "$VIVADO_BIN/../data/verilog/src/glbl.v")"
mkdir -p sim/build_xsim
cd sim/build_xsim
rm -rf xsim.dir

fail=0
# usage: run <label> <testbench module> <"plain"|"unisim"> <xvlog extra defines> <rtl files...>
run() {
  label=$1; tb=$2; kind=$3; defs=$4; shift 4
  srcs=""; for f in "$@"; do srcs="$srcs ../../$f"; done
  snap="${label}_snap"; log="$label.log"
  extra=""; [ "$kind" = unisim ] && extra="$GLBL"
  elab_libs=""; [ "$kind" = unisim ] && elab_libs="-L unisims_ver -L secureip glbl"
  {
    cmd //c "xvlog -sv $defs $srcs ../$tb.v $extra" &&
    cmd //c "xelab -debug typical $tb $elab_libs -s $snap" &&
    cmd //c "xsim $snap -R"
  } > "$log" 2>&1
  if grep -q "ALL CHECKS PASSED" "$log"; then echo "[PASS] $label"
  else echo "[FAIL] $label  (see sim/build_xsim/$log)"; tail -8 "$log" | sed 's/^/    /'; fail=1; fi
}

run tb_video_timing_gen tb_video_timing_gen plain "" rtl/video_timing_gen.v
run tb_colorbar_gen     tb_colorbar_gen     plain "" rtl/colorbar_gen.v
run tb_debounce         tb_debounce         plain "" rtl/debounce.v
run tb_tmds_encoder     tb_tmds_encoder     plain "" rtl/tmds_encoder.v
run tb_i2c_master       tb_i2c_master       plain "" rtl/i2c_master.v
run tb_cam_to_display   tb_cam_to_display   plain "" rtl/ov7670_capture.v rtl/rgb565_to_gray.v rtl/sobel_3x3.v rtl/frame_buffer.v rtl/pixel_reader.v rtl/cam_to_display.v rtl/video_timing_gen.v
run tb_ov7670_init      tb_ov7670_init      plain "" rtl/i2c_master.v rtl/ov7670_init.v
run tb_servo_pwm        tb_servo_pwm        plain "" rtl/servo_pwm.v

run tb_video_clocks     tb_video_clocks     unisim "" rtl/video_clocks.v
run tb_tmds_serializer  tb_tmds_serializer  unisim "" rtl/tmds_serializer.v

TOPSRC="rtl/video_clocks.v rtl/tmds_serializer.v rtl/tmds_encoder.v rtl/video_timing_gen.v rtl/colorbar_gen.v rtl/tmds_tx_lanes.v rtl/top_phase1_dvi.v rtl/top_dvi_svga.v rtl/top_dvi_720p.v"
run tb_top_640x480  tb_top_phase1_dvi unisim ""               $TOPSRC
run tb_top_800x600  tb_top_phase1_dvi unisim "-d MODE_SVGA"   $TOPSRC
run tb_top_1280x720 tb_top_phase1_dvi unisim "-d MODE_720P"   $TOPSRC

[ $fail -eq 0 ] && echo "All testbenches passed." || echo "Some testbenches FAILED."
exit $fail
