@echo off
rem Builds the Ethernet stream viewer with the .NET compiler that ships with Windows.
set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
"%CSC%" /nologo /target:winexe /out:"%~dp0stream_viewer.exe" /r:System.Windows.Forms.dll /r:System.Drawing.dll "%~dp0stream_viewer.cs"
