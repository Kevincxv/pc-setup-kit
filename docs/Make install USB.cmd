@echo off
title PC Setup Kit - install USB
echo.
echo  PC Setup Kit: making an install USB (Windows 11 + the kit, sets a new PC up by itself).
echo  It asks for administrator rights, then which USB stick to use - that stick gets ERASED.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f = Join-Path $env:TEMP 'pckit-make-usb.ps1'; irm https://github.com/Kevincxv/pc-setup-kit/releases/latest/download/make-usb.ps1 -OutFile $f; & $f"
