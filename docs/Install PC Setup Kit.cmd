@echo off
title PC Setup Kit - installer
echo.
echo  PC Setup Kit: starting the installer.
echo  It asks for administrator rights, shows what it will do and waits for you to type YES.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://github.com/Kevincxv/pc-setup-kit/releases/latest/download/install.ps1 | iex"
