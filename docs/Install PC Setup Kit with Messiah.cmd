@echo off
title PC Setup Kit with Messiah - installer
echo.
echo  PC Setup Kit with Messiah (Claude): starting the installer.
echo  It asks for administrator rights, shows what it will do and waits for you to type YES.
echo  Messiah needs your own Claude account (Pro or higher).
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://github.com/Kevincxv/pc-setup-kit/releases/latest/download/install.ps1))) -WithClaude"
