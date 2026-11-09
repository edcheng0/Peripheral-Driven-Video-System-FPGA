# Peripheral-Driven Video System (FPGA)

A live video pipeline in Verilog on the **Digilent Zybo Z7-20** (Zynq-7020).
An OV7670 camera is captured, filtered, and shown on a monitor over HDMI.
The HDMI signal is generated directly by the FPGA, with no video chip in between.

```
OV7670 camera --> capture --> filter --> frame buffer --> HDMI encoder --> monitor
                           (gray / edges / invert)
```

## Status

| Part | Status |
|---|---|
| HDMI output (color bars) | Working on hardware |
| Board bring-up (LEDs, buttons, switches) | Working on hardware |
| Camera capture, frame buffer, and filters (gray, edges, invert) | Working on hardware |
| ARM processor control of the filter mode over serial | Working on hardware (serial replies verified; filters confirmed on screen) |

## Demos

### HDMI color bars
_Photo coming soon._

### Live camera
_Photo or video coming soon._

### Filters (grayscale, edge detect, invert)
_Demo coming soon._

## What's inside

- **HDMI output:** TMDS encoding, 10:1 serializers and clock generation, written from the DVI spec. Runs at 640x480, 800x600 and 1280x720.
- **Camera input:** pixel capture and I2C-style configuration for the OV7670.
- **Filters:** grayscale, Sobel edge detection, and invert.
- **Frame buffer:** a dual-clock memory that safely passes pixels between the camera and display clocks.
- **ARM control:** a small ARM program sets the filter over the serial port through an AXI GPIO block.
- **Servo PWM:** a 50 Hz servo driver, ready for later use.
- **Tests:** every module has a self-checking testbench, and the full HDMI output is decoded and checked in simulation.

## Folders

```
rtl/          Verilog source
sw/           ARM (Zynq) software
sim/          testbenches
constraints/  pin assignments (from Digilent's Zybo Z7 pin file)
scripts/      simulate, build, and program scripts
```

## Run it

Needs Vivado with Zynq-7000 support (built with 2025.2).

```bash
bash scripts/run_sims_xsim.sh      # run all tests

# build the HDMI color bars
vivado -mode batch -source scripts/build.tcl -tclargs top_phase1_dvi zybo_clock.xdc zybo_hdmi_tx.xdc

# load it onto the board
vivado -mode batch -source scripts/program.tcl -tclargs build/top_phase1_dvi/top_phase1_dvi.bit
```

## Next

- Use DDR3 memory for a full 640x480 frame buffer
- More ARM control: servo, USB mouse, Ethernet
