# Peripheral-Driven Video System (FPGA)

A real-time video pipeline in plain Verilog for the **Digilent Zybo Z7-20**
(Xilinx Zynq-7020): an **OV7670 camera** is captured, filtered, buffered
across clock domains, and shown on a monitor through the board's **HDMI
output, with the DVI/HDMI video signal generated directly by the FPGA fabric**
(no HDMI transmitter chip involved).

```
OV7670 --8-bit parallel + PCLK--> capture --> gray / Sobel / invert --> dual-clock
 (SCCB config via I2C master)     (RGB565)                              frame buffer
                                                                            |
 HDMI TX pins <-- OSERDESE2 10:1 <-- TMDS 8b/10b <-- 2x upscale <-----------+
                  (126 MHz DDR)       encoders       (pixel clock domain)
```

> **Status:** everything below is verified in simulation and builds with
> timing met in Vivado. It has **not yet been run on hardware** (board and
> camera on order). The README will be updated with photos and results
> after bring-up. The OV7670 register values are unverified until then.

## What it demonstrates

| Skill | Where |
|---|---|
| High-speed serial I/O with Xilinx primitives (MMCM, OSERDESE2 master/slave 10:1 DDR, OBUFDS / TMDS_33) | `rtl/video_clocks.v`, `rtl/tmds_serializer.v` |
| DVI/HDMI protocol: TMDS 8b/10b encoding written from the spec, 4 control codes, sync on the blue lane | `rtl/tmds_encoder.v`, `rtl/tmds_tx_lanes.v` |
| Video timing for 640x480, 800x600 and 1280x720 @ 60 Hz | `rtl/video_timing_gen.v`, `rtl/top_dvi_*.v` |
| Camera interfacing: parallel capture in the camera's own clock domain, SCCB configuration | `rtl/ov7670_capture.v`, `rtl/ov7670_init.v`, `rtl/i2c_master.v` |
| Clock-domain crossing: dual-clock block-RAM frame buffer, 2-FF synchronizers, async clock groups | `rtl/frame_buffer.v`, `rtl/cam_to_display.v`, `constraints/zybo_camera_pmod.xdc` |
| Streaming image processing: grayscale (BT.601), 3x3 Sobel with line buffers, invert | `rtl/rgb565_to_gray.v`, `rtl/sobel_3x3.v` |
| Peripheral control: 50 Hz servo PWM | `rtl/servo_pwm.v` |
| Verification: self-checking testbenches, independent reference models, mutation checks | `sim/` |

## Verification approach

Every module has a self-checking testbench that prints
`=== ALL CHECKS PASSED ===`; `scripts/run_sims_xsim.sh` runs them all.

- **TMDS:** the encoder output is decoded with an independent reference
  decoder and must match all 256 byte values plus random data; running
  disparity is tracked. (A first version passed a "50/50 ones and zeros" check
  while being wrong. The decode round-trip is what caught it.)
- **Whole HDMI path:** the testbench acts as a DVI receiver. It finds word
  boundaries from the clock lane, decodes all three lanes, and checks a full
  visible line of color bars plus the blanking and hsync codes, for each of the
  three video modes.
- **Camera to display:** a behavioural OV7670 model sends a known image in
  RGB565 byte pairs. Every displayed pixel is compared with an independently
  computed expectation (raw, gray, Sobel, inverted). Deliberately breaking one
  Sobel coefficient makes this test fail.
- **SCCB:** a bit-level slave model decodes every I2C transaction. This found a
  real bug in the I2C master (no clock pulse for the ACK bit), now fixed.

## Repository layout

```
rtl/          synthesizable Verilog (thin wrappers around Xilinx primitives,
              all testable logic in plain modules)
sim/          self-checking testbenches
constraints/  XDC files, pins taken from Digilent's Zybo-Z7 master XDC
scripts/      run_sims_xsim.sh (all simulations), build.tcl (Vivado batch build),
              program.tcl (JTAG)
```

## Build and run

Needs Vivado (developed on 2025.2) with Zynq-7000 device support.

```bash
# simulate everything (Git Bash; set VIVADO_BIN if Vivado is not in the default path)
bash scripts/run_sims_xsim.sh

# build a bitstream
vivado -mode batch -nojournal -nolog -source scripts/build.tcl \
       -tclargs top_zybo_bringup zybo_clock.xdc zybo_leds.xdc zybo_switches.xdc zybo_buttons.xdc

vivado -mode batch -nojournal -nolog -source scripts/build.tcl \
       -tclargs top_phase1_dvi zybo_clock.xdc zybo_hdmi_tx.xdc          # HDMI color bars

vivado -mode batch -nojournal -nolog -source scripts/build.tcl \
       -tclargs top_camera_dvi zybo_clock.xdc zybo_hdmi_tx.xdc zybo_leds.xdc \
                zybo_switches.xdc zybo_camera_pmod.xdc                  # camera pipeline

# program the board
vivado -mode batch -nojournal -nolog -source scripts/program.tcl -tclargs build/top_phase1_dvi/top_phase1_dvi.bit
```

Camera top: switches SW1:SW0 select raw / gray / Sobel / invert.

## Roadmap

1. Bring-up on the Zybo: LEDs, then HDMI color bars (640x480, then higher modes).
2. Camera: verify OV7670 register settings, camera color bars, then live video.
3. Move the frame buffer to DDR3 through the Zynq PS (AXI VDMA) for full 640x480.
4. ARM (PS) control software: filter selection, servo commands, USB mouse input.
5. Gigabit Ethernet streaming through the PS.

## Design notes

- The pixel clock is 25.25 MHz (standard 25.175 MHz is 0.3 % away; monitors
  accept it) so the 5x serial clock is an exact integer multiple from one MMCM.
- The frame buffer is 320x240 RGB565 (1.23 Mb, 48.5 of the 140 block RAM tiles
  available) and is upscaled 2x on output.
- Sobel results exist only for interior pixels; the 1-pixel border is not written.
- The picture can tear because capture and display are not frame-synchronised.
