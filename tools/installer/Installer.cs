// Install-Messiah.exe: the download button's installer. It only starts the published one-line installer
// (install.ps1 from the latest GitHub release), which asks for administrator rights, shows what it will do and waits for
// YES. An .exe instead of a .cmd so it can carry a code signature (Windows then shows no "Windows protected your PC"
// warning). Built from this file by tools\installer\build.ps1 on GitHub for every release (sign.yml).
using System;
using System.Diagnostics;
using System.Reflection;

[assembly: AssemblyTitle("Messiah installer")]
[assembly: AssemblyDescription("Installs Messiah (PC Setup Kit) from github.com/Kevincxv/pc-setup-kit")]
[assembly: AssemblyProduct("Messiah")]
[assembly: AssemblyCompany("pc-setup-kit (open source)")]

static class Installer {
    const string Url = "https://github.com/Kevincxv/pc-setup-kit/releases/latest/download/install.ps1";
    static int Main() {
        Console.Title = "Messiah - installer";
        Console.WriteLine();
        Console.WriteLine("  Messiah: starting the installer.");
        Console.WriteLine("  It asks for administrator rights, shows what it will do and waits for you to type YES.");
        Console.WriteLine();
        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -Command \"irm " + Url + " | iex\"") { UseShellExecute = false };
        try {
            using (var p = Process.Start(psi)) { p.WaitForExit(); return p.ExitCode; }
        } catch (Exception e) {
            Console.WriteLine("  Couldn't start PowerShell: " + e.Message);
            Console.WriteLine("  Press Enter to close."); Console.ReadLine();
            return 1;
        }
    }
}
