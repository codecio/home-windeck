# SteamConsoleSetup — minimal nerdy admin guide

This toolkit turns a Windows 11 box into a couch-friendly Steam console: autologin, Steam Big Picture at logon, and power tweaks to keep the machine awake. Designed for a single-purpose living-room PC — admin-controlled, reversible.

Quick start (do this first)

1. Open an elevated PowerShell prompt.
2. Run a dry-run to preview changes:  .\Setup-SteamConsole.ps1 -DryRun
3. Run for real:  .\Setup-SteamConsole.ps1
4. Reboot and verify (see checks below).

What runs by default

- AutoLogin (uses Sysinternals Autologon when available; falls back to registry)
- SteamInstall (winget Valve.Steam)
- SteamStartup (schtasks -> steam.exe -bigpicture -silent)
- DesktopFriction (disables the full lock-screen overlay)
- PowerTweaks (sets never-sleep / never-display-off)

Notes & warnings (read this)

- AutoLogin stores credentials: we prefer Autologon.exe (LSA secret). If unavailable the script writes DefaultPassword to HKLM\...\Winlogon (backed up). Local admins can still recover secrets.
- NVIDIA driver install is opt-in and may require reboot; uninstall is manual and destructive to game libraries if done carelessly.
- Backups and logs: backups/ and logs/ are created (ignored by git). Use them to roll back.

Post-reboot quick checks

Run these to validate the setup:

Get-ScheduledTask -TaskName 'SteamConsoleSetup-BigPictureAutostart' | Format-List *
schtasks /Query /TN "SteamConsoleSetup-BigPictureAutostart" /XML
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
powercfg /L

Reverting

To undo changes:  .\Setup-SteamConsole.ps1 -Revert

If you need a surgical rollback, import the .reg files from backups/ with reg import.

If you want cleaner controller support outside Steam, consider DS4Windows (ViGEm) for system-wide mapping; otherwise use Steam Input in Big Picture.

Want me to push these README edits and tag a release? Or run the reboot+verify step now and capture logs?