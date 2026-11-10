# ----------------------------------------------------------------------
# make_ddr_sw.py - builds the ARM DDR frame-buffer program (sw/ddr_framebuffer)
# for the design made by make_ddr_system.tcl, with Vitis' Python CLI:
#   vitis -s scripts/make_ddr_sw.py
# Output: build/vitis_ddr/ddr/build/ddr.elf
# ----------------------------------------------------------------------
import os
import shutil
import vitis

root = os.getcwd().replace("\\", "/")
ws = root + "/build/vitis_ddr"
xsa = root + "/build/ddr_system/ddr_system.xsa"

shutil.rmtree(ws, ignore_errors=True)
client = vitis.create_client()
client.set_workspace(path=ws)

plat = client.create_platform_component(
    name="sys_plat", hw_design=xsa, os="standalone", cpu="ps7_cortexa9_0")
plat.build()

xpfm = ws + "/sys_plat/export/sys_plat/sys_plat.xpfm"
app = client.create_app_component(
    name="ddr", platform=xpfm, domain="standalone_ps7_cortexa9_0",
    template="hello_world")

# replace the template's main file (keep its name so its build file still works)
src_dir = ws + "/ddr/src"
shutil.copy(root + "/sw/ddr_framebuffer/main.c", src_dir + "/helloworld.c")

app.build()
print("SW BUILD OK")
vitis.dispose()
