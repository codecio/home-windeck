# Home-WinDeck

A sysadmin-style reference and quick guide for converting a Windows 11 machine into a Steam-first console. Focuses on reliable, reversible changes that are safe for home use.

Table of contents

- Quick start
- Modules (summary)
- Safety & backups
- Post-reboot verification
- Troubleshooting
- Roadmap

Quick start

| Action | Command |
|---|---|
| Preview (no changes) | .\Setup-SteamConsole.ps1 -DryRun |
| Apply defaults | .\Setup-SteamConsole.ps1 |
| Revert defaults | .\Setup-SteamConsole.ps1 -Revert |
| Apply specific modules | .\Setup-SteamConsole.ps1 -Modules AutoLogin,SteamStartup -User gamer |

Modules (summary)

| Module | Purpose | Changes | Revert |
|---|---|---|---|
| AutoLogin | Auto sign-in at boot | Prefers Sysinternals Autologon (stores LSA secret). If unavailable, writes DefaultPassword to `HKLM\\...\\Winlogon` (backed up). | Disable-AutoLogin / `.\Setup-SteamConsole.ps1 -Revert` |
| SteamInstall | Install Steam | `winget install --id Valve.Steam` (idempotent) | Manual uninstall (advisory) |
| SteamStartup | Auto-launch Steam Big Picture | Creates `Home-WinDeck-BigPictureAutostart` via `schtasks` | `.\Setup-SteamConsole.ps1 -Revert` |
| DesktopFriction | Remove full-screen lock overlay | Sets policy `NoLockScreen=1` at `HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\Personalization` | `.\Setup-SteamConsole.ps1 -Revert` |
| PowerTweaks | Console power profile | Activates a high-perf-like scheme, disables hibernate, sets never-display/never-sleep | Disable-PowerTweaks (restores previous scheme) |
| NvidiaDriver (opt-in) | GPU driver install | Installs `Nvidia.GraphicsDriver` via winget (requires `-Yes`) | Manual uninstall (advisory) |

Safety & backups

- All registry keys the script touches are exported to `backups/` before modification.
- The script writes a transcript to `logs/` (both paths are in `.gitignore`).
- Use `-DryRun` to preview actions before they change the system.
- Autologon: script will download Autologon.zip from Sysinternals into `tools/` by default and use it to store credentials as an LSA secret. If that fails, the registry fallback is used (with backup).
- LSA-stored secrets are better than plaintext but can still be retrieved by a local admin.

Post-reboot verification (commands)

```powershell
# Task
Get-ScheduledTask -TaskName 'Home-WinDeck-BigPictureAutostart' | Format-List *
# Task XML
schtasks /Query /TN "Home-WinDeck-BigPictureAutostart" /XML
# Winlogon entries
reg query "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon"
# Power schemes
powercfg /L
powercfg /query
```

Troubleshooting (short)

- `winget` missing → install App Installer from Microsoft Store.
- Steam not launching via task → run Steam manually once; check Task Scheduler history.
- `schtasks` errors → check logs in `logs/` and `schtasks /Query` output.

Roadmap

- Controller helpers: Steam Input presets, DS4Windows guidance
- PowerTweaks refinements (multimedia rules, USB selective suspend)
- CI (PSScriptAnalyzer) & tests

License

No license file included — contact the repository owner.

---

If you want expanded module docs or an operator checklist, say which module and I'll generate a focused markdown file.