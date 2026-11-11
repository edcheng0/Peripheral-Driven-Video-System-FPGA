# ----------------------------------------------------------------------
# make_eth_sw.py - builds the ARM program WITH Ethernet video streaming:
# the same program as sw/ddr_framebuffer (VDMA, camera, servo, filters) plus the lwIP
# network stack and net_stream.c.  Uses the hardware from make_ddr_system.tcl.
#   vitis -s scripts/make_eth_sw.py
# Output: build/vitis_eth/eth.elf (+ ps7_init.tcl)
#
# The workspace is outside the repo on a SHORT path on purpose: the lwIP library has very
# long file names and Windows' 260-character path limit breaks the build in a deep folder.
# Set FW_WS to use another folder (a fresh one if Vitis says the workspace is in use).
# ----------------------------------------------------------------------
import os
import shutil
import vitis

root = os.getcwd().replace("\\", "/")
ws = os.environ.get("FW_WS", "C:/fw/vitis_eth").replace("\\", "/")
xsa = root + "/build/ddr_system/ddr_system.xsa"

shutil.rmtree(ws, ignore_errors=True)
client = vitis.create_client()
client.set_workspace(path=ws)

plat = client.create_platform_component(
    name="sys_plat", hw_design=xsa, os="standalone", cpu="ps7_cortexa9_0")
dom = plat.get_domain(name="standalone_ps7_cortexa9_0")
dom.set_lib(lib_name="lwip220")
plat.build()

xpfm = ws + "/sys_plat/export/sys_plat/sys_plat.xpfm"
app = client.create_app_component(
    name="eth", platform=xpfm, domain="standalone_ps7_cortexa9_0",
    template="hello_world")

src_dir = ws + "/eth/src"
# our program: main.c with the Ethernet part switched on, plus the network code
shutil.copy(root + "/sw/ddr_framebuffer/net_stream.c", src_dir + "/net_stream.c")
shutil.copy(root + "/sw/ddr_framebuffer/net_stream.h", src_dir + "/net_stream.h")
with open(root + "/sw/ddr_framebuffer/main.c") as f:
    main_c = f.read()
with open(src_dir + "/helloworld.c", "w") as f:
    f.write("#define ETHERNET 1\n" + main_c)

# tell the build to compile the network file too
cfg = src_dir + "/UserConfig.cmake"
with open(cfg) as f:
    txt = f.read()
with open(cfg, "w") as f:
    f.write(txt.replace('"platform.c"', '"platform.c"\n"net_stream.c"', 1))

app.build()

# put the results inside the repo build folder, where scripts/run_eth.tcl looks for them
out = root + "/build/vitis_eth"
shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)
shutil.copy(ws + "/eth/build/eth.elf", out + "/eth.elf")
shutil.copy(ws + "/eth/_ide/psinit/ps7_init.tcl", out + "/ps7_init.tcl")
print("SW BUILD OK")
vitis.dispose()
