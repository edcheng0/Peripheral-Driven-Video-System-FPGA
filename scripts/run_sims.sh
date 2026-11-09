#!/usr/bin/env bash
# ----------------------------------------------------------------------
# run_sims.sh - run every self-checking testbench with Icarus Verilog.
# Usage (from project root):  bash scripts/run_sims.sh
# Each testbench prints "=== ALL CHECKS PASSED ===" on success.
# Exits non-zero if any testbench fails, times out, or doesn't compile.
# ----------------------------------------------------------------------
set -u
cd "$(dirname "$0")/.."
mkdir -p sim/build

# testbench name | RTL files it needs
TESTS=(
  "tb_video_timing_gen|rtl/video_timing_gen.v"
  "tb_colorbar_gen|rtl/colorbar_gen.v"
  "tb_debounce|rtl/debounce.v"
  "tb_tmds_encoder|rtl/tmds_encoder.v"
  "tb_i2c_master|rtl/i2c_master.v"
  "tb_cam_to_display|rtl/ov7670_capture.v rtl/rgb565_to_gray.v rtl/sobel_3x3.v rtl/frame_buffer.v rtl/pixel_reader.v rtl/cam_to_display.v rtl/video_timing_gen.v"
  "tb_ov7670_init|rtl/i2c_master.v rtl/ov7670_rom.v rtl/ov7670_init.v"
  "tb_servo_pwm|rtl/servo_pwm.v"
)

fail=0
for entry in "${TESTS[@]}"; do
  tb="${entry%%|*}"
  srcs="${entry#*|}"
  out="sim/build/${tb}.vvp"
  if ! iverilog -g2012 -Wall -o "$out" $srcs "sim/${tb}.v" 2> "sim/build/${tb}.compile.log"; then
    echo "[COMPILE FAIL] $tb  (see sim/build/${tb}.compile.log)"; fail=1; continue
  fi
  result=$(cd sim/build && vvp "${tb}.vvp" 2>&1)
  if echo "$result" | grep -q "ALL CHECKS PASSED"; then
    echo "[PASS] $tb"
  else
    echo "[FAIL] $tb"; echo "$result" | sed 's/^/    /'; fail=1
  fi
done

[ $fail -eq 0 ] && echo "All testbenches passed." || echo "Some testbenches FAILED."
exit $fail
