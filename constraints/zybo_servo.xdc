# Servo signal on Pmod JE pin 1 (JE1 = V12 in Digilent's Zybo Z7-20 board file).
# Servo ground goes to Pmod JE pin 5 (GND).
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { servo }]
