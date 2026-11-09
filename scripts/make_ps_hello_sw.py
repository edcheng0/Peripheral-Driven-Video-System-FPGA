# ----------------------------------------------------------------------
# make_ps_hello_sw.py - builds the ARM "hello world" program for the
# processor design made by make_ps_hello.tcl, using Vitis' Python CLI:
#   vitis -s scripts/make_ps_hello_sw.py
# Output: build/vitis_ws/hello/build/hello.elf  (path may vary by version)
# ----------------------------------------------------------------------
import os
import vitis

root = os.getcwd().replace("\\", "/")
ws = root + "/build/vitis_ws"
xsa = root + "/build/ps_hello/ps_hello.xsa"

client = vitis.create_client()
client.set_workspace(path=ws)

plat = client.create_platform_component(
    name="zybo_plat", hw_design=xsa, os="standalone", cpu="ps7_cortexa9_0")
plat.build()

xpfm = ws + "/zybo_plat/export/zybo_plat/zybo_plat.xpfm"
app = client.create_app_component(
    name="hello", platform=xpfm, domain="standalone_ps7_cortexa9_0",
    template="hello_world")
app.build()
print("SW BUILD OK")
vitis.dispose()
