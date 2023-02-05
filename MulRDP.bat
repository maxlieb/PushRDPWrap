@echo off
powershell -ep bypass -noprofile -nologo -file "%~dp0MulRDP.ps1" %*
pause
