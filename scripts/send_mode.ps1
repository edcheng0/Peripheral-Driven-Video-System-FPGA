# send_mode.ps1 - set the video filter on the Zybo from a Windows terminal.
#   powershell -File scripts/send_mode.ps1 2
# Modes: 0 raw color, 1 grayscale, 2 edge detect, 3 invert.
# Needs the ARM filter-control program to be running (scripts/run_system.tcl).
# Change $port if the board's serial port is not COM4 (see Device Manager).
param([Parameter(Mandatory = $true)][ValidateSet('0','1','2','3')][string]$mode,
      [string]$port = 'COM4')
$p = New-Object System.IO.Ports.SerialPort $port,115200,None,8,One
$p.ReadTimeout = 500
$p.Open()
$p.Write($mode)
Start-Sleep -Milliseconds 500
$reply = $p.ReadExisting().Trim()
$p.Close()
if ($reply) { $reply } else { "sent mode $mode (no reply)" }
