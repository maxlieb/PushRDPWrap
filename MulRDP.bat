@echo off
::mkdir "\\%1\c$\Program Files\RDP Wrapper\"
::copy "c:\users\m21372\OneDrive - Netafim\Tools\RDPWrap\*" "\\%1\c$\Program Files\RDP Wrapper\" /Y
::psexec -s \\%1 "C:\Program Files\RDP Wrapper\autoupdate.bat"
::echo Install done, have your session and when done return to this window, press enter to uninstall.
::echo (quit this window now if you don't want to uninstall).
::pause
::psexec -s \\%1 "C:\Program Files\RDP Wrapper\uninstall.bat"
powershell -ep bypass -noprofile -nologo -file "%~dp0MulRDP.ps1" %*
pause